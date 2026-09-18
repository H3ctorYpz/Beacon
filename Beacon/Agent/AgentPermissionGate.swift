import AppKit
import Foundation

@MainActor
enum AgentPermissionGate {
    /// Session remembers: toolName -> allowed
    private static var sessionAllow: Set<String> = []

    static func resetSession() {
        sessionAllow.removeAll()
    }

    static func confirm(tool: AgentToolName, detail: String) async -> Bool {
        if !tool.requiresConfirmation { return true }
        if sessionAllow.contains(tool.rawValue) { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Beacon pide permiso"
        alert.informativeText = "\(tool.title)\n\n\(detail)\n\n¿Permitir esta acción?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Permitir")
        alert.addButton(withTitle: "Permitir por esta sesión")
        alert.addButton(withTitle: "Denegar")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            sessionAllow.insert(tool.rawValue)
            return true
        default:
            return false
        }
    }
}
