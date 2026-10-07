import AppKit

/// Turns macOS's own ⌘Tab / ⌘⇧Tab app switcher off while Switcher handles those keys.
///
/// The setting lives in the window server, not in this process, so it would outlive a crash.
/// Every exit path therefore turns it back on: normal quit, termination signals, crash signals
/// and uncaught exceptions. Only SIGKILL can't be caught; relaunching Switcher repairs that case.
enum NativeCommandTab {
    private static let commandTab: Int32 = 1
    private static let commandShiftTab: Int32 = 2

    static func setEnabled(_ enabled: Bool) {
        PrivateAPI.setSymbolicHotKey(commandTab, enabled: enabled)
        PrivateAPI.setSymbolicHotKey(commandShiftTab, enabled: enabled)
    }

    static var isEnabled: Bool {
        PrivateAPI.isSymbolicHotKeyEnabled(commandTab)
    }

    static func installSafetyNet() {
        // Resolve the symbols now: lazy initialisation inside a signal handler could deadlock
        _ = isEnabled

        atexit {
            NativeCommandTab.setEnabled(true)
        }

        for signalNumber in [SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(signalNumber) { received in
                NativeCommandTab.setEnabled(true)
                // Let the default action (exit or crash report) happen
                signal(received, SIG_DFL)
                raise(received)
            }
        }

        NSSetUncaughtExceptionHandler { _ in
            NativeCommandTab.setEnabled(true)
        }
    }
}
