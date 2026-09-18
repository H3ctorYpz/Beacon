import AppKit

/// Menu-bar entry. Left click opens a real menu (not a silent island toggle),
/// so Settings is always reachable.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let onToggleIsland: () -> Void
    private let onTogglePill: () -> Void
    private let onOpenSettings: () -> Void
    private var isIslandExpanded: () -> Bool
    private var isPillVisible: () -> Bool
    private let accounts: AIAccountStore

    init(
        accounts: AIAccountStore = .shared,
        onToggleIsland: @escaping () -> Void,
        onTogglePill: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        isIslandExpanded: @escaping () -> Bool = { true },
        isPillVisible: @escaping () -> Bool = { true }
    ) {
        self.accounts = accounts
        self.onToggleIsland = onToggleIsland
        self.onTogglePill = onTogglePill
        self.onOpenSettings = onOpenSettings
        self.isIslandExpanded = isIslandExpanded
        self.isPillVisible = isPillVisible
    }

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Dynamic Island pill silhouette — black capsule on transparent, as template.
            // AppIcon is full-color and becomes a white square when isTemplate=true.
            let icon = Self.makeIslandMenuBarIcon(pointSize: 18)
            icon.isTemplate = true
            button.image = icon
            button.toolTip = "Beacon"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleTitle = isIslandExpanded() ? "Collapse Island" : "Expand Island"
        let toggle = menu.addItem(withTitle: toggleTitle, action: #selector(toggleIsland), keyEquivalent: "b")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        toggle.target = self

        let pillTitle = isPillVisible() ? "Hide Pill" : "Show Pill"
        let pill = menu.addItem(withTitle: pillTitle, action: #selector(togglePill), keyEquivalent: "h")
        pill.keyEquivalentModifierMask = [.command, .shift]
        pill.target = self

        menu.addItem(.separator())

        let accountsMenu = NSMenu(title: "AI Account")
        if accounts.accounts.isEmpty {
            let empty = accountsMenu.addItem(withTitle: "No accounts — open Settings", action: #selector(openSettings), keyEquivalent: "")
            empty.target = self
        } else {
            for account in accounts.accounts {
                let title = "\(account.name) · \(account.shortLabel)"
                let item = accountsMenu.addItem(withTitle: title, action: #selector(selectAccount(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = account.id.uuidString
                if account.id == accounts.activeAccountId {
                    item.state = .on
                }
            }
        }
        let accountsItem = NSMenuItem(title: "AI Account", action: nil, keyEquivalent: "")
        accountsItem.submenu = accountsMenu
        menu.addItem(accountsItem)

        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command
        settings.target = self

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit Beacon", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
    }

    @objc private func toggleIsland() {
        onToggleIsland()
    }

    @objc private func togglePill() {
        onTogglePill()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw)
        else { return }
        accounts.setActive(id)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Classic Dynamic Island capsule (~4.5:1) for the menu bar.
    /// Drawn black on transparent so `isTemplate = true` adapts to light/dark bar.
    private static func makeIslandMenuBarIcon(pointSize: CGFloat) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { bounds in
            // Island proportions: wide horizontal pill, vertically centered.
            let islandHeight = bounds.height * 0.34
            let islandWidth = min(bounds.width * 0.92, islandHeight * 4.5)
            let rect = NSRect(
                x: (bounds.width - islandWidth) / 2,
                y: (bounds.height - islandHeight) / 2,
                width: islandWidth,
                height: islandHeight
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: islandHeight / 2, yRadius: islandHeight / 2)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
