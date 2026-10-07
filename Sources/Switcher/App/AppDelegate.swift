import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keeps App Nap away: a napping background app answered the first ⌘Tab after a pause late
    private var latencyActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, no Dock icon
        NSApp.setActivationPolicy(.accessory)
        latencyActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "⌘Tab must open instantly"
        )

        // Whatever happens to this process from now on, macOS gets its own ⌘Tab back
        NativeCommandTab.installSafetyNet()
        // A previous run killed with SIGKILL may have left it off
        NativeCommandTab.setEnabled(true)

        StatusBarController.shared.setup()
        SwitcherController.shared.start()

        let defaults = UserDefaults.standard
        if !Permissions.accessibility || (!Permissions.screenRecording && !defaults.bool(forKey: "onboardingShown")) {
            OnboardingController.shared.show()
            defaults.set(true, forKey: "onboardingShown")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SwitcherController.shared.stop()
    }
}
