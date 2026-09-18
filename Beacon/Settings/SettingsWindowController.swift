import AppKit
import SwiftUI

/// Dedicated settings window. Menu-bar apps with `LSUIElement` often never
/// receive SwiftUI's `showSettingsWindow:` — this AppKit window always works.
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsView>?
    private var closeObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    func show(
        preferences: AppPreferences = .shared,
        accounts: AIAccountStore = .shared
    ) {
        let root = SettingsView(preferences: preferences, accounts: accounts)

        if let hosting {
            hosting.rootView = root
        } else {
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Beacon Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 540))
            window.minSize = NSSize(width: 640, height: 420)
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .normal
            self.hosting = hosting
            self.window = window

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    if !AppPreferences.shared.showDockIcon {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }

        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
