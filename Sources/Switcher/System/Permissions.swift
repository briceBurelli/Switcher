import AppKit
import ApplicationServices

enum Permissions {
    /// Needed to intercept ⌘Tab and to raise one precise window
    static var accessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Needed only for window previews
    static var screenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Adds Switcher to the Accessibility list (switched off) and shows the system prompt
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
    }

    /// First time: the system prompt (it adds Switcher to the list). Afterwards macOS no longer
    /// prompts, so go straight to the right page of System Settings.
    static func requestScreenRecording() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "screenRecordingRequested") {
            openSettings("Privacy_ScreenCapture")
        } else {
            defaults.set(true, forKey: "screenRecordingRequested")
            CGRequestScreenCaptureAccess()
        }
    }

    static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
