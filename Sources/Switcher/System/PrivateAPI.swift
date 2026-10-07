import ApplicationServices
import CoreGraphics
import Foundation

/// Undocumented system functions that window switchers (AltTab, Hammerspoon, Witch…) rely on.
/// Resolved at runtime so a missing symbol degrades gracefully instead of crashing at launch.
enum PrivateAPI {
    nonisolated(unsafe) private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func function<T>(_ name: String, in handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    // MARK: - Window identity

    private typealias AXGetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let axGetWindow = function("_AXUIElementGetWindow", in: nil, as: AXGetWindowFunction.self)

    /// The CGWindowID behind an Accessibility window element
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let axGetWindow else { return nil }
        var id: CGWindowID = 0
        return axGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    // MARK: - Symbolic hot keys (⌘Tab = 1, ⌘⇧Tab = 2)

    private typealias SetSymbolicHotKeyFunction = @convention(c) (Int32, Bool) -> CGError
    private typealias IsSymbolicHotKeyFunction = @convention(c) (Int32) -> Bool
    private static let setSymbolicHotKeyEnabled = function("CGSSetSymbolicHotKeyEnabled", in: skyLight, as: SetSymbolicHotKeyFunction.self)
    private static let isSymbolicHotKeyEnabled = function("CGSIsSymbolicHotKeyEnabled", in: skyLight, as: IsSymbolicHotKeyFunction.self)

    static var canToggleSymbolicHotKeys: Bool { setSymbolicHotKeyEnabled != nil }

    static func setSymbolicHotKey(_ hotKey: Int32, enabled: Bool) {
        _ = setSymbolicHotKeyEnabled?(hotKey, enabled)
    }

    static func isSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool {
        isSymbolicHotKeyEnabled?(hotKey) ?? true
    }

    // MARK: - Bringing one precise window to the front

    private typealias GetProcessForPIDFunction = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessFunction = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordFunction = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private static let getProcessForPID = function("GetProcessForPID", in: nil, as: GetProcessForPIDFunction.self)
    private static let setFrontProcess = function("_SLPSSetFrontProcessWithOptions", in: skyLight, as: SetFrontProcessFunction.self)
    private static let postEventRecord = function("SLPSPostEventRecordTo", in: skyLight, as: PostEventRecordFunction.self)

    /// Activates the app with exactly this window in front and key — what a click on the window would do.
    /// Ported from AltTab, itself from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
    static func bringToFront(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let getProcessForPID, let setFrontProcess, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }

        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }

        // Two synthetic window-server event records make the window key
        for kind: UInt8 in [0x01, 0x02] {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x08] = kind
            bytes[0x3a] = 0x10
            withUnsafeBytes(of: windowID) { id in
                for (offset, byte) in id.enumerated() {
                    bytes[0x3c + offset] = byte
                }
            }
            for offset in 0x20..<0x30 {
                bytes[offset] = 0xff
            }
            _ = bytes.withUnsafeMutableBufferPointer { buffer in
                postEventRecord(&psn, buffer.baseAddress!)
            }
        }
        return true
    }
}
