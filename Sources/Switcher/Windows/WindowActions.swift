import AppKit
import ApplicationServices

@MainActor
enum WindowActions {
    /// Brings exactly this window to the front, un-minimizing or un-hiding it if needed
    static func focus(_ item: WindowItem, element: AXUIElement?) {
        guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else { return }

        if app.isHidden {
            app.unhide()
        }

        guard let windowID = item.windowID, let element else {
            // No window open: activate the app, as macOS's ⌘Tab does
            activate(app)
            return
        }

        if item.isMinimized {
            AX.set(element, kAXMinimizedAttribute, false)
        }
        if !PrivateAPI.bringToFront(pid: item.pid, windowID: windowID) {
            activate(app)
        }
        // Raise it above the app's other windows (e.g. the compose window over the inbox)
        AX.set(element, kAXMainAttribute, true)
        AX.perform(element, kAXRaiseAction)
    }

    private static func activate(_ app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if !AX.set(axApp, kAXFrontmostAttribute, true) {
            app.activate()
        }
    }

    static func close(_ element: AXUIElement?) {
        guard let element, let closeButton = AX.element(element, kAXCloseButtonAttribute) else { return }
        AX.perform(closeButton, kAXPressAction)
    }

    static func minimize(_ element: AXUIElement?) {
        guard let element else { return }
        AX.set(element, kAXMinimizedAttribute, true)
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    static func hide(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }
}
