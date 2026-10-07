import Carbon
import CoreGraphics
import Foundation
import os

private let debugLog = Logger(subsystem: "com.stack.switcher", category: "tap")

/// What the keyboard asks of an open switcher
enum SwitcherCommand: Sendable {
    /// ⌘Tab pressed while the switcher was closed
    case open(backward: Bool)
    case move(Int)
    case moveRow(Int)
    case commit
    /// ⌘ released: confirm the selection
    case release
    case cancel
    case closeWindow
    case quitApp
    case hideApp
    case minimizeWindow
}

/// Session keyboard tap, on its own thread so a busy main thread never lags typing.
///
/// Idle, it lets every event through untouched. While the switcher is open it swallows keys
/// (so ⌘W, ⌘Q or arrows don't reach the frontmost app) and turns them into commands,
/// and reports the release of ⌘ that confirms the choice.
final class KeyboardTap: @unchecked Sendable {
    private let lock = NSLock()
    private var switching = false
    /// ⌘ as last seen in real keyboard events. Unlike querying the session's modifier state,
    /// this is never stale (the query reported ⌘ released on the first ⌘Tab after a pause).
    private var commandDown = false
    /// Uptime (ns) of the last ⌘Tab key press, to measure how fast the switcher reacts
    private var lastCommandTabPress: UInt64 = 0
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var onCommand: (@Sendable (SwitcherCommand) -> Void)?

    var isSwitching: Bool {
        get { lock.withLock { switching } }
        set { lock.withLock { switching = newValue } }
    }

    var lastCommandTabPressNanos: UInt64 {
        lock.withLock { lastCommandTabPress }
    }

    var isCommandDown: Bool {
        lock.withLock { commandDown }
    }

    var isHealthy: Bool {
        lock.withLock { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    }

    /// Requires Accessibility. `onCommand` is called on the tap thread.
    func start(onCommand: @escaping @Sendable (SwitcherCommand) -> Void) -> Bool {
        if lock.withLock({ tap != nil }) { return true }
        self.onCommand = onCommand

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let machPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: keyboardTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        lock.withLock { tap = machPort }

        nonisolated(unsafe) let port = machPort
        let thread = Thread { [weak self] in
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            let loop = CFRunLoopGetCurrent()
            self?.lock.withLock { self?.runLoop = loop }
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Switcher keyboard tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func stop() {
        let (machPort, loop) = lock.withLock { () -> (CFMachPort?, CFRunLoop?) in
            defer {
                tap = nil
                runLoop = nil
                switching = false
            }
            return (tap, runLoop)
        }
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
        }
        if let loop {
            CFRunLoopStop(loop)
        }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let machPort = lock.withLock({ tap }) {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            return passThrough

        case .flagsChanged:
            let isDown = event.flags.contains(.maskCommand)
            let released = lock.withLock { () -> Bool in
                commandDown = isDown
                guard switching, !isDown else { return false }
                switching = false
                return true
            }
            if released {
                if switcherDebug {
                    debugLog.notice("[debug] flagsChanged while switching: flags=0x\(String(event.flags.rawValue, radix: 16), privacy: .public) keycode=\(event.getIntegerValueField(.keyboardEventKeycode)) source=\(event.getIntegerValueField(.eventSourceStateID)) pid=\(event.getIntegerValueField(.eventSourceUnixProcessID))")
                }
                onCommand?(.release)
            }
            return passThrough

        case .keyDown, .keyUp:
            let flags = event.flags
            let isCommandTab = event.getIntegerValueField(.keyboardEventKeycode) == kVK_Tab
                && flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
            let wasSwitching = lock.withLock { () -> Bool in
                commandDown = flags.contains(.maskCommand)
                let was = switching
                if isCommandTab, type == .keyDown {
                    lastCommandTabPress = event.timestamp
                    switching = true
                }
                return was
            }

            // ⌘Tab is handled right here, on the very first press: the hot key alone
            // missed the first ⌘Tab after a pause
            if isCommandTab {
                if type == .keyDown {
                    let backward = flags.contains(.maskShift)
                    onCommand?(wasSwitching ? .move(backward ? -1 : 1) : .open(backward: backward))
                }
                return nil
            }

            guard wasSwitching else { return passThrough }
            if type == .keyDown, let command = command(for: event) {
                onCommand?(command)
                if case .cancel = command { isSwitching = false }
                if case .commit = command { isSwitching = false }
            }
            // Nothing typed while choosing reaches the app underneath
            return nil

        default:
            return passThrough
        }
    }

    private func command(for event: CGEvent) -> SwitcherCommand? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Tab:
            return .move(event.flags.contains(.maskShift) ? -1 : 1)
        case kVK_LeftArrow:
            return .move(-1)
        case kVK_RightArrow:
            return .move(1)
        case kVK_UpArrow:
            return .moveRow(-1)
        case kVK_DownArrow:
            return .moveRow(1)
        case kVK_Escape:
            return .cancel
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            return .commit
        default:
            break
        }

        // Letters depend on the layout (AZERTY swaps Q and A), so read the typed character
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &characters)
        switch String(utf16CodeUnits: characters, count: length).lowercased() {
        case "w": return .closeWindow
        case "q": return .quitApp
        case "h": return .hideApp
        case "m": return .minimizeWindow
        default: return nil
        }
    }
}

private func keyboardTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyboardTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
