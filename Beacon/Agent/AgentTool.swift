import Foundation

struct AgentToolCall: Equatable {
    let name: String
    let arguments: [String: String]
}

enum AgentToolName: String, CaseIterable {
    case run_terminal
    case read_file
    case write_file
    case list_dir
    case search_files
    case open_url
    case open_path
    case reveal_in_finder
    case clipboard_get
    case clipboard_set
    case system_info
    case run_applescript
    case get_frontmost_app

    var title: String {
        switch self {
        case .run_terminal: return "Ejecutar terminal"
        case .read_file: return "Leer archivo"
        case .write_file: return "Escribir archivo"
        case .list_dir: return "Listar carpeta"
        case .search_files: return "Buscar archivos"
        case .open_url: return "Abrir URL"
        case .open_path: return "Abrir ruta"
        case .reveal_in_finder: return "Mostrar en Finder"
        case .clipboard_get: return "Leer portapapeles"
        case .clipboard_set: return "Escribir portapapeles"
        case .system_info: return "Info del sistema"
        case .run_applescript: return "AppleScript"
        case .get_frontmost_app: return "App en primer plano"
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .system_info, .clipboard_get, .get_frontmost_app, .list_dir:
            return false
        default:
            return true
        }
    }
}

enum AgentToolCatalog {
    static var systemPromptAppendix: String {
        """
        You can act on the user's Mac through Beacon tools. Dangerous actions require the user to approve a dialog.

        When you need a tool, reply with ONLY valid JSON (no markdown fences):
        {"beacon_tools":[{"name":"TOOL_NAME","arguments":{"key":"value"}}]}

        When answering the user normally, reply with plain text (no JSON).

        Available tools:
        - run_terminal: {"command":"ls ~/Desktop"}
        - read_file: {"path":"/Users/me/file.txt"}
        - write_file: {"path":"/Users/me/file.txt","content":"..."}
        - list_dir: {"path":"~/Documents"}
        - search_files: {"query":"invoice pdf"}  (Spotlight)
        - open_url: {"url":"https://example.com"}
        - open_path: {"path":"~/Desktop/file.pdf"}
        - reveal_in_finder: {"path":"~/Desktop"}
        - clipboard_get: {}
        - clipboard_set: {"text":"..."}
        - system_info: {}
        - run_applescript: {"script":"tell application \\"Safari\\" to activate"}
        - get_frontmost_app: {}

        Rules:
        - Prefer the least invasive tool.
        - Never invent tool results; wait for Beacon to return them.
        - After tool results, either call more tools or give the final answer in plain text.
        - Paths may use ~ for the home folder.
        """
    }

    static func parseToolCalls(from reply: String) -> [AgentToolCall]? {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = extractJSONObject(from: trimmed)?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = json["beacon_tools"] as? [[String: Any]],
              !tools.isEmpty
        else { return nil }

        var calls: [AgentToolCall] = []
        for tool in tools {
            guard let name = tool["name"] as? String else { continue }
            var args: [String: String] = [:]
            if let rawArgs = tool["arguments"] as? [String: Any] {
                for (k, v) in rawArgs {
                    args[k] = String(describing: v)
                }
            } else if let rawArgs = tool["arguments"] as? [String: String] {
                args = rawArgs
            }
            calls.append(AgentToolCall(name: name, arguments: args))
        }
        return calls.isEmpty ? nil : calls
    }

    /// Pull a JSON object from a reply that may include prose or fences.
    private static func extractJSONObject(from text: String) -> String? {
        if text.hasPrefix("{"), text.hasSuffix("}") { return text }
        if let start = text.range(of: "```json")?.upperBound
            ?? text.range(of: "```")?.upperBound {
            let rest = text[start...]
            if let end = rest.range(of: "```") {
                return String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            return String(text[start...end])
        }
        return nil
    }
}
