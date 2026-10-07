import AppKit
import ServiceManagement

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        SwitcherController.shared.onStateChange = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        // A warning badge when ⌘Tab is not taken over (missing permission)
        let symbol = SwitcherController.shared.isEnabled ? "rectangle.on.rectangle" : "rectangle.on.rectangle.slash"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Switcher")
            ?? NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Switcher")
        image?.isTemplate = true
        button.image = image
        button.toolTip = SwitcherController.shared.isEnabled ? "Switcher — ⌘Tab par fenêtre" : "Switcher — en attente de l'autorisation Accessibilité"
    }

    // Rebuilt at every opening so the status and checkmarks are current
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let titleItem = NSMenuItem(title: "Switcher — ⌘Tab par fenêtre", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let active = SwitcherController.shared.isEnabled
        let statusItem = NSMenuItem(title: active ? "● Actif : ⌘Tab affiche vos fenêtres" : "⚠︎ Inactif : autorisez l'Accessibilité", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        let permissionsItem = NSMenuItem(title: "Autorisations…", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let loginItem = NSMenuItem(title: "Ouvrir au démarrage", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quitter Switcher (rend ⌘Tab à macOS)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func showPermissions() {
        OnboardingController.shared.show()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
