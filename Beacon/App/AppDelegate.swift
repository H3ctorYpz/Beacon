import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences.shared
    private let accounts = AIAccountStore.shared
    private lazy var conversation = ConversationStore(preferences: preferences, accounts: accounts)
    private var islandPanel: IslandPanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(preferences.showDockIcon ? .regular : .accessory)

        islandPanel = IslandPanelController(
            store: conversation,
            preferences: preferences,
            accounts: accounts,
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        statusItem = StatusItemController(
            accounts: accounts,
            onToggleIsland: { [weak self] in self?.islandPanel?.toggle() },
            onTogglePill: { [weak self] in self?.islandPanel?.togglePillVisible(animated: true) },
            onOpenSettings: { [weak self] in self?.openSettings() },
            isIslandExpanded: { [weak self] in self?.islandPanel?.isExpanded ?? false },
            isPillVisible: { [weak self] in self?.islandPanel?.isPillVisible ?? true }
        )
        statusItem?.install()
        registerMainMenu()

        // Keep Google Gemini ready (URL + model). User pastes API key in Settings.
        accounts.ensurePreset(.googleGemini, makeActive: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.islandPanel?.presentPinned()
        }

        if UserDefaults.standard.bool(forKey: "beacon.revealSettingsOnce") {
            UserDefaults.standard.set(false, forKey: "beacon.revealSettingsOnce")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.openSettings()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func registerMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Beacon")
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Beacon", action: #selector(openSettings), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Beacon",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        let openItem = windowMenu.addItem(
            withTitle: "Expand Island",
            action: #selector(openIsland),
            keyEquivalent: "b"
        )
        openItem.target = self
        openItem.keyEquivalentModifierMask = [.command, .shift]

        let pillItem = windowMenu.addItem(
            withTitle: "Toggle Pill Visibility",
            action: #selector(togglePill),
            keyEquivalent: "h"
        )
        pillItem.target = self
        pillItem.keyEquivalentModifierMask = [.command, .shift]

        NSApp.mainMenu = mainMenu
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show(preferences: preferences, accounts: accounts)
    }

    @objc private func openIsland() {
        islandPanel?.show()
    }

    @objc private func togglePill() {
        islandPanel?.togglePillVisible(animated: true)
    }
}
