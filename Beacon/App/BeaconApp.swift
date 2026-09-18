import SwiftUI

@main
struct BeaconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings UI is an AppKit window (SettingsWindowController).
        // Empty Settings scene keeps ⌘, wired if the system asks for it.
        Settings {
            EmptyView()
        }
    }
}
