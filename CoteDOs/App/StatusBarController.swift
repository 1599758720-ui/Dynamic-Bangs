import AppKit
import ServiceManagement

final class StatusBarController: NSObject, NSMenuItemValidation {
    private let statusItem: NSStatusItem
    private let settingsWindow = SettingsWindowController()
    private let onToggleNotch: () -> Void
    /// Whether the island currently sits somewhere the user dragged it — the
    /// reset item is dead weight otherwise, so it enables on this.
    private let isNotchPlaced: () -> Bool
    private let onResetPlacement: () -> Void
    private var pauseItem: NSMenuItem?
    private let onOpenTimer: () -> Void
    private let onOpenDashboard: () -> Void
    private let onOpenQuickActions: () -> Void

    init(onToggleNotch: @escaping () -> Void,
         isNotchPlaced: @escaping () -> Bool,
         onResetPlacement: @escaping () -> Void,
         onOpenTimer: @escaping () -> Void,
         onOpenDashboard: @escaping () -> Void,
         onOpenQuickActions: @escaping () -> Void) {
        self.onOpenDashboard = onOpenDashboard
        self.onOpenQuickActions = onOpenQuickActions
        self.onOpenTimer = onOpenTimer
        self.onToggleNotch = onToggleNotch
        self.isNotchPlaced = isNotchPlaced
        self.onResetPlacement = onResetPlacement
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = AppBrand.statusIcon()
            button.toolTip = AppBrand.name
        }

        let menu = NSMenu()
        let dashboardItem = NSMenuItem(title: "展开工作台", action: #selector(openDashboard), keyEquivalent: "")
        dashboardItem.target = self
        menu.addItem(dashboardItem)
        let searchItem = NSMenuItem(title: "快速搜索…", action: #selector(openQuickActions), keyEquivalent: "k")
        searchItem.keyEquivalentModifierMask = [.command, .option]
        searchItem.target = self
        menu.addItem(searchItem)
        let widgetsItem = NSMenuItem(title: "组件与缩略显示…", action: #selector(openWidgets), keyEquivalent: "")
        widgetsItem.target = self
        menu.addItem(widgetsItem)
        let timerItem = NSMenuItem(title: "打开番茄钟", action: #selector(openTimer), keyEquivalent: "")
        timerItem.target = self
        menu.addItem(timerItem)
        menu.addItem(.separator())


        // ⌥⌘N is registered globally via HotKeyCenter; the key equivalent here
        // is display only, so the menu teaches the shortcut.
        let pauseItem = NSMenuItem(
            title: String(localized: "menu.pauseNotch", defaultValue: "Notch pausieren"),
            action: #selector(toggleNotch),
            keyEquivalent: "n"
        )
        pauseItem.keyEquivalentModifierMask = [.command, .option]
        pauseItem.target = self
        menu.addItem(pauseItem)
        self.pauseItem = pauseItem

        let resetPlacementItem = NSMenuItem(
            title: String(localized: "menu.resetPlacement", defaultValue: "Notch zurück nach oben"),
            action: #selector(resetPlacement),
            keyEquivalent: ""
        )
        resetPlacementItem.target = self
        menu.addItem(resetPlacementItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: String(localized: "menu.launchAtLogin", defaultValue: "Bei Anmeldung starten"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "menu.settings", defaultValue: "Einstellungen …"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: String(localized: "menu.quit", defaultValue: "Quit Dynamic Bangs"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    /// Reflect the pause state in the menu (checkmark) and the status icon
    /// (outline instead of filled), whichever of the two routes flipped it.
    func setNotchPaused(_ paused: Bool) {
        pauseItem?.state = paused ? .on : .off
        statusItem.button?.image = AppBrand.statusIcon(paused: paused)
    }

    @objc private func toggleNotch() {
        onToggleNotch()
    }

    @objc private func openTimer() { onOpenTimer() }
    @objc private func openDashboard() { onOpenDashboard() }
    @objc private func openQuickActions() { onOpenQuickActions() }
    @objc private func openWidgets() { WidgetPreferencesWindow.shared.show() }

    @objc private func resetPlacement() {
        onResetPlacement()
    }

    /// The menu auto-enables its items through this: only the reset item has
    /// anything to say, and only while the island is off its home pose.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(resetPlacement) else { return true }
        return isNotchPlaced()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            NSLog("CoteDOs: launch-at-login toggle failed: \(error)")
        }
    }

    @objc func openSettings() {
        settingsWindow.show()
    }
}
