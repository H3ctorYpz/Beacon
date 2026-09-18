import AppKit
import Foundation

@MainActor
enum AgentExecutor {
    static func run(_ call: AgentToolCall) async -> String {
        guard let tool = AgentToolName(rawValue: call.name) else {
            return "Error: unknown tool \(call.name)"
        }

        let detail = summary(for: tool, args: call.arguments)
        let allowed = await AgentPermissionGate.confirm(tool: tool, detail: detail)
        guard allowed else { return "Denied by user." }

        do {
            switch tool {
            case .run_terminal:
                return try runTerminal(call.arguments["command"] ?? "")
            case .read_file:
                return try readFile(call.arguments["path"] ?? "")
            case .write_file:
                return try writeFile(path: call.arguments["path"] ?? "", content: call.arguments["content"] ?? "")
            case .list_dir:
                return try listDir(call.arguments["path"] ?? "~")
            case .search_files:
                return try searchFiles(call.arguments["query"] ?? "")
            case .open_url:
                return try openURL(call.arguments["url"] ?? "")
            case .open_path:
                return try openPath(call.arguments["path"] ?? "")
            case .reveal_in_finder:
                return try revealInFinder(call.arguments["path"] ?? "")
            case .clipboard_get:
                return NSPasteboard.general.string(forType: .string) ?? "(empty clipboard)"
            case .clipboard_set:
                let text = call.arguments["text"] ?? ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                return "Clipboard updated (\(text.count) chars)."
            case .system_info:
                return systemInfo()
            case .run_applescript:
                return try runAppleScript(call.arguments["script"] ?? "")
            case .get_frontmost_app:
                return frontmostApp()
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func summary(for tool: AgentToolName, args: [String: String]) -> String {
        switch tool {
        case .run_terminal: return args["command"] ?? ""
        case .read_file, .open_path, .reveal_in_finder, .list_dir: return args["path"] ?? ""
        case .write_file: return "\(args["path"] ?? "") (\(args["content"]?.count ?? 0) chars)"
        case .search_files: return args["query"] ?? ""
        case .open_url: return args["url"] ?? ""
        case .clipboard_set: return String((args["text"] ?? "").prefix(120))
        case .run_applescript: return String((args["script"] ?? "").prefix(200))
        default: return tool.title
        }
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func runTerminal(_ command: String) throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Error: empty command" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", trimmed]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var result = stdout
        if !stderr.isEmpty { result += (result.isEmpty ? "" : "\n") + "stderr:\n" + stderr }
        result += "\n[exit \(process.terminationStatus)]"
        return String(result.prefix(12_000))
    }

    private static func readFile(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: expand(path))
        let data = try Data(contentsOf: url)
        if data.count > 200_000 {
            return "Error: file too large (\(data.count) bytes). Max ~200KB."
        }
        return String((String(data: data, encoding: .utf8) ?? "(binary or non-UTF8)").prefix(12_000))
    }

    private static func writeFile(path: String, content: String) throws -> String {
        let url = URL(fileURLWithPath: expand(path))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.data(using: .utf8)?.write(to: url)
        return "Wrote \(content.count) chars to \(url.path)"
    }

    private static func listDir(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: expand(path))
        let items = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
        return items.prefix(400).joined(separator: "\n") + (items.count > 400 ? "\n… (\(items.count) total)" : "")
    }

    private static func searchFiles(_ query: String) throws -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return "Error: empty query" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", NSHomeDirectory(), q]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n").prefix(40)
        return lines.isEmpty ? "(no results)" : lines.joined(separator: "\n")
    }

    private static func openURL(_ raw: String) throws -> String {
        guard let url = URL(string: raw), url.scheme == "http" || url.scheme == "https" else {
            return "Error: invalid http(s) URL"
        }
        NSWorkspace.shared.open(url)
        return "Opened \(url.absoluteString)"
    }

    private static func openPath(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: expand(path))
        guard FileManager.default.fileExists(atPath: url.path) else { return "Error: path not found" }
        NSWorkspace.shared.open(url)
        return "Opened \(url.path)"
    }

    private static func revealInFinder(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: expand(path))
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return "Revealed \(url.path)"
    }

    private static func systemInfo() -> String {
        let host = ProcessInfo.processInfo
        return """
        host: \(Host.current().localizedName ?? "Mac")
        user: \(NSUserName())
        home: \(NSHomeDirectory())
        os: \(host.operatingSystemVersionString)
        cores: \(host.processorCount)
        memory: \(host.physicalMemory / 1_048_576) MB
        uptime: \(Int(host.systemUptime))s
        """
    }

    private static func runAppleScript(_ script: String) throws -> String {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Error: empty script" }
        var error: NSDictionary?
        if let result = NSAppleScript(source: trimmed)?.executeAndReturnError(&error) {
            return result.stringValue ?? "OK"
        }
        if let error {
            return "Error: \(error)"
        }
        return "Error: AppleScript failed"
    }

    private static func frontmostApp() -> String {
        if let app = NSWorkspace.shared.frontmostApplication {
            return "\(app.localizedName ?? "Unknown") (\(app.bundleIdentifier ?? "no-bundle"))"
        }
        return "(none)"
    }
}
