import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "com.stack.switcher", category: "windows")

/// One entry of the switcher: a window, or an app that has none open
struct WindowItem: Identifiable, Equatable {
    let id: String
    let windowID: CGWindowID?
    let pid: pid_t
    let appName: String
    let title: String
    var isMinimized: Bool
    var isHidden: Bool

    var isWindowless: Bool { windowID == nil }
    var displayTitle: String { title.isEmpty ? appName : title }

    static func window(_ windowID: CGWindowID, pid: pid_t, appName: String, title: String, isMinimized: Bool, isHidden: Bool) -> WindowItem {
        WindowItem(id: "w\(windowID)", windowID: windowID, pid: pid, appName: appName, title: title, isMinimized: isMinimized, isHidden: isHidden)
    }

    static func app(pid: pid_t, appName: String, isHidden: Bool) -> WindowItem {
        WindowItem(id: "a\(pid)", windowID: nil, pid: pid, appName: appName, title: "", isMinimized: false, isHidden: isHidden)
    }
}

/// Lists every switchable window, most recently used first, the way Windows' Alt-Tab does
@MainActor
final class WindowList {
    private var elements: [String: AXUIElement] = [:]
    /// Apps by last activation, most recent first
    private var recentApps: [pid_t] = []

    init() {
        if let front = NSWorkspace.shared.frontmostApplication {
            recentApps = [front.processIdentifier]
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            MainActor.assumeIsolated {
                self?.recentApps.removeAll { $0 == pid }
                self?.recentApps.insert(pid, at: 0)
            }
        }
    }

    func element(for item: WindowItem) -> AXUIElement? {
        elements[item.id]
    }

    func snapshot() -> [WindowItem] {
        elements.removeAll()
        let ownPID = getpid()
        let zOrder = Self.onScreenOrder()

        var visible: [(z: Int, item: WindowItem)] = []
        var background: [WindowItem] = [] // minimized, hidden app, other Space
        var windowless: [WindowItem] = []

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated
        }

        for app in apps {
            let appStart = Date()
            defer {
                let elapsed = Int(Date().timeIntervalSince(appStart) * 1000)
                if switcherDebug, elapsed >= 20 {
                    log.notice("[debug] slow app \(app.localizedName ?? "?", privacy: .public): \(elapsed) ms")
                }
            }
            let pid = app.processIdentifier
            let name = app.localizedName ?? "App"
            let axApp = AXUIElementCreateApplication(pid)
            // A frozen app must not freeze ⌘Tab
            AXUIElementSetMessagingTimeout(axApp, 0.2)

            var windowCount = 0
            for window in AX.windows(of: axApp) {
                let attributes = AX.attributes(of: window)
                guard Self.isSwitchable(attributes), let windowID = PrivateAPI.windowID(of: window) else { continue }

                let item = WindowItem.window(
                    windowID,
                    pid: pid,
                    appName: name,
                    title: attributes.title ?? "",
                    isMinimized: attributes.isMinimized,
                    isHidden: app.isHidden
                )
                elements[item.id] = window
                windowCount += 1

                if let z = zOrder[windowID], !attributes.isMinimized {
                    visible.append((z, item))
                } else {
                    background.append(item)
                }
            }

            if windowCount == 0 {
                windowless.append(.app(pid: pid, appName: name, isHidden: app.isHidden))
            }
        }

        let rank = Dictionary(recentApps.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let byRecency: (WindowItem, WindowItem) -> Bool = { (rank[$0.pid] ?? .max) < (rank[$1.pid] ?? .max) }

        return visible.sorted { $0.z < $1.z }.map(\.item)
            + background.sorted(by: byRecency)
            + windowless.sorted(by: byRecency)
    }

    /// Real windows only: no palettes, tooltips, popovers or invisible helper windows
    private static func isSwitchable(_ attributes: AX.WindowAttributes) -> Bool {
        guard attributes.role == kAXWindowRole,
              attributes.subrole == kAXStandardWindowSubrole || attributes.subrole == kAXDialogSubrole else { return false }
        if let size = attributes.size, size.width < 60 || size.height < 40 {
            return false
        }
        return true
    }

    /// Front-to-back position of every normal window currently on screen. Activating a window
    /// brings it to the front, so this is also the most-recently-used order.
    private static func onScreenOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        for (index, info) in list.enumerated() {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? Int else { continue }
            order[CGWindowID(number)] = index
        }
        return order
    }
}
