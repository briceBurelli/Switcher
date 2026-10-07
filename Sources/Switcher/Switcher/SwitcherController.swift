import AppKit
import Carbon
import SwiftUI
import os

private let log = Logger(subsystem: "com.stack.switcher", category: "switcher")
/// `defaults write com.stack.switcher SwitcherDebug -bool true` logs timings of every ⌘Tab
let switcherDebug = UserDefaults.standard.bool(forKey: "SwitcherDebug")

/// ⌘Tab state machine: open on ⌘Tab, move with Tab / ⇧Tab / arrows / mouse, switch on ⌘ release.
@MainActor
final class SwitcherController {
    static let shared = SwitcherController()

    static let cardWidth: CGFloat = 220
    static let cardHeight: CGFloat = 190
    static let cardSpacing: CGFloat = 12

    let model = SwitcherModel()
    /// Called when Switcher starts or stops replacing ⌘Tab (menu bar status)
    var onStateChange: (() -> Void)?
    private(set) var isEnabled = false

    private let windowList = WindowList()
    private let thumbnails = ThumbnailProvider()
    private let hotKeys = CommandTabHotKeys()
    private let tap = KeyboardTap()
    private let panel = SwitcherPanel()

    private var isSwitching = false
    private var releasePoll: Timer?
    private var permissionMonitor: Timer?
    private var mouseLocationAtOpen: NSPoint = .zero

    private init() {
        let view = SwitcherView(
            model: model,
            onSizeChange: { [weak self] size in self?.panel.resize(to: size) },
            onHover: { [weak self] index in self?.hover(index) },
            onClick: { [weak self] index in self?.click(index) },
            onClose: { [weak self] index in self?.close(at: index) }
        )
        let hostingView = FirstMouseHostingView(rootView: view)
        // panel.resize(to:) owns the size; don't let the hosting view impose window min/max sizes
        hostingView.sizingOptions = []
        panel.contentView = hostingView
    }

    // MARK: - Replacing ⌘Tab

    func start() {
        if switcherDebug {
            // Lets the panel be opened and photographed without touching the keyboard
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.stack.switcher.debugOpen"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let controller = SwitcherController.shared
                    controller.open(backward: false, simulated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        DebugScreen.capture(controller.panel.frame)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { controller.finish() }
                    }
                }
            }
        }
        if switcherDebug {
            for run in 1...2 {
                let start = Date()
                let count = windowList.snapshot().count
                log.notice("[debug] launch snapshot #\(run): \(count) items in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            }
        }
        enableIfPossible()
        startPermissionMonitor()
    }

    func stop() {
        permissionMonitor?.invalidate()
        permissionMonitor = nil
        disable()
    }

    func enableIfPossible() {
        guard !isEnabled, Permissions.accessibility, PrivateAPI.canToggleSymbolicHotKeys else { return }

        let started = tap.start { command in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    SwitcherController.shared.handle(command)
                }
            }
        }
        guard started else {
            log.error("Keyboard tap unavailable; leaving macOS ⌘Tab in place")
            return
        }

        hotKeys.register()
        NativeCommandTab.setEnabled(false)
        isEnabled = true
        log.notice("⌘Tab now switches windows")
        onStateChange?()
    }

    func disable() {
        finish()
        hotKeys.unregister()
        tap.stop()
        NativeCommandTab.setEnabled(true)
        if isEnabled {
            isEnabled = false
            onStateChange?()
        }
    }

    /// Takes over ⌘Tab as soon as Accessibility is granted (whichever window the user granted it from),
    /// and hands it back to macOS if the permission is revoked or the tap dies
    private func startPermissionMonitor() {
        permissionMonitor?.invalidate()
        permissionMonitor = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let controller = SwitcherController.shared
                if controller.isEnabled {
                    guard !Permissions.accessibility || !controller.tap.isHealthy else { return }
                    log.error("Accessibility or keyboard tap lost; restoring macOS ⌘Tab")
                    controller.disable()
                } else if Permissions.accessibility {
                    controller.enableIfPossible()
                }
            }
        }
    }

    // MARK: - Keyboard

    func hotKeyPressed(backward: Bool) {
        // The tap already opened the switcher for this press; the hot key only covers secure input
        guard !canTrustTap else { return }
        if switcherDebug {
            let pressed = tap.lastCommandTabPressNanos
            let delay = pressed > 0 ? Int((clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - pressed) / 1_000_000) : -1
            log.notice("[debug] hot key, switching=\(self.isSwitching) reaction=\(delay) ms after the key press")
        }
        if isSwitching {
            move(backward ? -1 : 1)
        } else {
            open(backward: backward)
        }
    }

    func handle(_ command: SwitcherCommand) {
        if case let .open(backward) = command {
            if isSwitching {
                move(backward ? -1 : 1)
            } else {
                open(backward: backward)
            }
            return
        }
        guard isSwitching else { return }
        switch command {
        case .open: break
        case let .move(delta): move(delta)
        case let .moveRow(delta): move(delta * model.columns)
        case .commit: commit(reason: "key")
        case .release: commit(reason: "⌘ released")
        case .cancel: finish()
        case .closeWindow: closeSelectedWindow()
        case .quitApp: quitSelectedApp()
        case .hideApp: hideSelectedApp()
        case .minimizeWindow: minimizeSelectedWindow()
        }
    }

    // MARK: - Flow

    private func open(backward: Bool, simulated: Bool = false) {
        if switcherDebug {
            let pressed = tap.lastCommandTabPressNanos
            let delay = pressed > 0 ? Int((clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - pressed) / 1_000_000) : -1
            log.notice("[debug] open from \(simulated ? "debug" : "⌘Tab", privacy: .public), \(delay) ms after the key press")
        }
        let start = Date()
        let items = windowList.snapshot()
        if switcherDebug { log.notice("[debug] listed \(items.count) items in \(Int(Date().timeIntervalSince(start) * 1000)) ms") }
        guard !items.isEmpty else {
            tap.isSwitching = false
            return
        }

        isSwitching = true
        tap.isSwitching = true
        model.forgetIcons()
        model.items = items
        model.thumbnails = thumbnails.cached(for: items)
        // Like Alt-Tab: the first press lands on the previous window
        model.selectedIndex = items.count > 1 ? (backward ? items.count - 1 : 1) : 0

        // Shown on every ⌘Tab, even a quick tap: it then fades out as the window comes forward
        showPanel()

        if simulated {
            return
        } else if canTrustTap {
            // ⌘ was already let go before this hot key got here: a quick ⌘Tab
            if !tap.isCommandDown {
                commit(reason: "quick tap")
            }
        } else {
            startReleasePolling()
        }
    }

    /// The tap sees every key event except while secure input is on (password fields),
    /// where the release has to be polled instead
    private var canTrustTap: Bool {
        tap.isHealthy && !IsSecureEventInputEnabled()
    }

    private func showPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSPointInRect(mouse, $0.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        let available = visible.width * 0.92 - 40
        let fit = max(1, Int((available + Self.cardSpacing) / (Self.cardWidth + Self.cardSpacing)))
        model.columns = min(fit, max(model.items.count, 1))
        model.maxVisibleRows = max(1, Int((visible.height * 0.8 - 110) / (Self.cardHeight + Self.cardSpacing)))

        mouseLocationAtOpen = mouse
        panel.present(centeredIn: visible)

        // Re-render once the window is really on screen, as the second Tab used to
        DispatchQueue.main.async { [weak self] in
            self?.model.objectWillChange.send()
        }
        if switcherDebug {
            let panel = self.panel
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            let order = model.items.prefix(4).map { "\($0.appName)\($0.isWindowless ? "(app)" : "")" }.joined(separator: ", ")
            log.notice("[debug] panel shown, front app=\(front, privacy: .public) order=[\(order, privacy: .public)] selected=\(self.model.selectedIndex) visible=\(panel.occlusionState.contains(.visible))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                log.notice("[debug] panel +250 ms, visible=\(panel.occlusionState.contains(.visible)) onScreen=\(panel.isVisible)")
            }
        }

        thumbnails.refresh(model.items) { [weak self] id, image in
            self?.model.thumbnails[id] = image
        }
    }

    private func commit(reason: String) {
        if switcherDebug { log.notice("[debug] commit by \(reason, privacy: .public), switching=\(self.isSwitching) selected=\(self.model.selectedIndex)") }
        guard isSwitching, let item = model.selectedItem else {
            finish()
            return
        }
        let element = windowList.element(for: item)
        finish()
        WindowActions.focus(item, element: element)
    }

    private func finish() {
        isSwitching = false
        tap.isSwitching = false
        releasePoll?.invalidate()
        releasePoll = nil
        panel.dismiss()
    }

    /// Secure-input fallback: reads the keyboard hardware state, and only believes a release
    /// seen on two consecutive ticks so one stale reading can't close the panel
    private func startReleasePolling() {
        releasePoll?.invalidate()
        var upReadings = 0
        releasePoll = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            MainActor.assumeIsolated {
                let isDown = CGEventSource.flagsState(.hidSystemState).contains(.maskCommand)
                upReadings = isDown ? 0 : upReadings + 1
                if upReadings >= 2 {
                    SwitcherController.shared.commit(reason: "release poll (secure input)")
                }
            }
        }
    }

    private func move(_ delta: Int) {
        let count = model.items.count
        guard count > 0 else { return }
        model.selectedIndex = ((model.selectedIndex + delta) % count + count) % count
    }

    // MARK: - Mouse

    private func hover(_ index: Int) {
        // The panel opens under a still cursor: only a real mouse move changes the selection
        let mouse = NSEvent.mouseLocation
        guard hypot(mouse.x - mouseLocationAtOpen.x, mouse.y - mouseLocationAtOpen.y) > 3 else { return }
        if model.items.indices.contains(index) {
            model.selectedIndex = index
        }
    }

    private func click(_ index: Int) {
        guard model.items.indices.contains(index) else { return }
        model.selectedIndex = index
        commit(reason: "click")
    }

    // MARK: - Actions on the selection (W, Q, H, M)

    private func closeSelectedWindow() {
        close(at: model.selectedIndex)
    }

    /// The card's × button: closes the window, or quits an app that has none open
    private func close(at index: Int) {
        guard model.items.indices.contains(index) else { return }
        let item = model.items[index]
        if item.isWindowless {
            WindowActions.quit(pid: item.pid)
            remove { $0.pid == item.pid }
        } else {
            WindowActions.close(windowList.element(for: item))
            remove { $0.id == item.id }
        }
    }

    private func quitSelectedApp() {
        guard let item = model.selectedItem else { return }
        WindowActions.quit(pid: item.pid)
        remove { $0.pid == item.pid }
    }

    private func hideSelectedApp() {
        guard let item = model.selectedItem else { return }
        WindowActions.hide(pid: item.pid)
        for index in model.items.indices where model.items[index].pid == item.pid {
            model.items[index].isHidden = true
        }
    }

    private func minimizeSelectedWindow() {
        guard let item = model.selectedItem, !item.isWindowless else { return }
        WindowActions.minimize(windowList.element(for: item))
        model.items[model.selectedIndex].isMinimized = true
    }

    private func remove(where predicate: (WindowItem) -> Bool) {
        model.items.removeAll(where: predicate)
        if model.items.isEmpty {
            finish()
        } else {
            model.selectedIndex = min(model.selectedIndex, model.items.count - 1)
        }
    }
}

/// Lets a click on a card count even though the panel is never the key window
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
