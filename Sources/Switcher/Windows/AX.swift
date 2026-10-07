import ApplicationServices
import CoreGraphics

/// Small typed helpers over the Accessibility C API
enum AX {
    static func windows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    struct WindowAttributes {
        var role: String?
        var subrole: String?
        var title: String?
        var isMinimized = false
        var size: CGSize?
    }

    /// One round trip to the app for everything the switcher needs about a window
    static func attributes(of window: AXUIElement) -> WindowAttributes {
        let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute, kAXSizeAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(window, names, AXCopyMultipleAttributeOptions(), &values) == .success,
              let list = values as? [AnyObject], list.count == 5 else { return WindowAttributes() }

        var attributes = WindowAttributes()
        attributes.role = list[0] as? String
        attributes.subrole = list[1] as? String
        attributes.title = list[2] as? String
        attributes.isMinimized = (list[3] as? Bool) ?? false
        if CFGetTypeID(list[4]) == AXValueGetTypeID() {
            var size = CGSize.zero
            if AXValueGetValue(list[4] as! AXValue, .cgSize, &size) {
                attributes.size = size
            }
        }
        return attributes
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }
}
