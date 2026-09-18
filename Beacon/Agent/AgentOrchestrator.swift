import Foundation

@MainActor
enum AgentOrchestrator {
    static let maxRounds = 6

    static func run(
        messages: [ChatMessage],
        baseSystemPrompt: String,
        agentEnabled: Bool,
        accounts: AIAccountStore,
        onStatus: ((String) -> Void)? = nil
    ) async throws -> String {
        var working = messages
        let system: String
        if agentEnabled {
            system = baseSystemPrompt + "\n\n" + AgentToolCatalog.systemPromptAppendix
        } else {
            system = baseSystemPrompt
        }

        for round in 0..<maxRounds {
            onStatus?(round == 0 ? "Thinking…" : "Tool round \(round)…")
            let reply = try await AIRouter.complete(
                messages: working,
                systemPrompt: system,
                store: accounts
            )

            guard agentEnabled,
                  let calls = AgentToolCatalog.parseToolCalls(from: reply),
                  !calls.isEmpty
            else {
                return reply
            }

            working.append(ChatMessage(role: .assistant, content: reply))

            var results: [String] = []
            for call in calls {
                onStatus?("\(AgentToolName(rawValue: call.name)?.title ?? call.name)…")
                let result = await AgentExecutor.run(call)
                results.append("[\(call.name)]\n\(result)")
            }

            let bundled = """
            Tool results for Beacon (do not invent; use these facts). If you need more tools, emit beacon_tools JSON again. Otherwise answer the user in plain text.
            \(results.joined(separator: "\n\n"))
            """
            working.append(ChatMessage(role: .user, content: bundled))
        }

        return "Reached the tool-round limit. Ask me to continue if needed."
    }
}
