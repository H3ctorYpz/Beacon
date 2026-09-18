import Foundation

struct OpenAICompatibleClient: AIProviding {
    let baseURL: String
    let model: String
    let apiKey: String
    let requiresKey: Bool

    func complete(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if requiresKey && key.isEmpty {
            throw AIClientError.missingAPIKey
        }

        guard let url = Self.chatCompletionsURL(from: baseURL) else {
            throw AIClientError.invalidURL
        }

        var payload: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for message in messages where message.role != .system {
            payload.append([
                "role": message.role.rawValue,
                "content": message.content,
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": payload,
            "stream": false,
            "temperature": 0.6,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIClientError.transport("Unexpected response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw AIClientError.badStatus(http.statusCode, AIHTTP.friendlyBody(text))
            }
            if let content = Self.extractContent(from: data) {
                return content
            }
            throw AIClientError.emptyResponse
        } catch let error as AIClientError {
            throw error
        } catch {
            throw AIClientError.transport(error.localizedDescription)
        }
    }

    private static func extractContent(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first
        else { return nil }

        if let message = first["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let parts = message["content"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        if let text = first["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func chatCompletionsURL(from base: String) -> URL? {
        var raw = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        if raw.isEmpty { return nil }
        if raw.hasSuffix("/chat/completions") {
            return URL(string: raw)
        }
        // OpenAI SDK behavior: baseURL + "/chat/completions" (do not invent /v1).
        return URL(string: raw + "/chat/completions")
    }
}

struct AnthropicClient: AIProviding {
    let baseURL: String
    let model: String
    let apiKey: String

    func complete(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { throw AIClientError.missingAPIKey }

        guard let url = Self.messagesURL(from: baseURL) else {
            throw AIClientError.invalidURL
        }

        let anthropicMessages: [[String: String]] = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        guard !anthropicMessages.isEmpty else {
            throw AIClientError.emptyResponse
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": anthropicMessages,
        ]
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIClientError.transport("Unexpected response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw AIClientError.badStatus(http.statusCode, AIHTTP.friendlyBody(text))
            }
            if let content = Self.extractContent(from: data) {
                return content
            }
            throw AIClientError.emptyResponse
        } catch let error as AIClientError {
            throw error
        } catch {
            throw AIClientError.transport(error.localizedDescription)
        }
    }

    private static func messagesURL(from base: String) -> URL? {
        var raw = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        if raw.isEmpty { return nil }
        if raw.hasSuffix("/v1/messages") {
            return URL(string: raw)
        }
        if raw.hasSuffix("/v1") {
            return URL(string: raw + "/messages")
        }
        return URL(string: raw + "/v1/messages")
    }

    private static func extractContent(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else { return nil }
        let text = content.compactMap { part -> String? in
            guard (part["type"] as? String) == "text" else { return nil }
            return part["text"] as? String
        }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct GeminiClient: AIProviding {
    let baseURL: String
    let model: String
    let apiKey: String

    func complete(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { throw AIClientError.missingAPIKey }

        guard let url = Self.generateContentURL(baseURL: baseURL, model: model) else {
            throw AIClientError.invalidURL
        }

        // Gemini uses role "user" / "model" (not assistant).
        var contents: [[String: Any]] = []
        for message in messages where message.role == .user || message.role == .assistant {
            let role = message.role == .assistant ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": message.content]],
            ])
        }
        guard !contents.isEmpty else { throw AIClientError.emptyResponse }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.6,
            ],
        ]
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            body["system_instruction"] = [
                "parts": [["text": system]],
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIClientError.transport("Unexpected response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw AIClientError.badStatus(http.statusCode, AIHTTP.friendlyBody(text))
            }
            if let content = Self.extractContent(from: data) {
                return content
            }
            throw AIClientError.emptyResponse
        } catch let error as AIClientError {
            throw error
        } catch {
            throw AIClientError.transport(error.localizedDescription)
        }
    }

    private static func normalizeModel(_ model: String) -> String {
        var m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.hasPrefix("models/") {
            m = String(m.dropFirst("models/".count))
        }
        return m
    }

    private static func generateContentURL(baseURL: String, model: String) -> URL? {
        let modelID = normalizeModel(model)
        guard !modelID.isEmpty else { return nil }

        var raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        if raw.isEmpty { return nil }

        // Accept either native base or leftover OpenAI-compat base from older builds.
        if raw.contains("/openai") {
            raw = raw.replacingOccurrences(of: "/openai", with: "")
            while raw.hasSuffix("/") { raw.removeLast() }
        }
        if raw.hasSuffix("/v1beta") == false && raw.contains("generativelanguage.googleapis.com") {
            if raw.hasSuffix("/v1") {
                raw += "beta"
            } else {
                raw += "/v1beta"
            }
        }

        return URL(string: "\(raw)/models/\(modelID):generateContent")
    }

    private static func extractContent(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { return nil }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
enum AIRouter {
    static func provider(for account: AIAccount, apiKey: String) -> any AIProviding {
        // Prefer native Gemini whenever the account points at Google Generative Language.
        if account.kind == .googleGemini || account.baseURL.contains("generativelanguage.googleapis.com") {
            return GeminiClient(
                baseURL: account.baseURL,
                model: account.model,
                apiKey: apiKey
            )
        }

        switch account.kind {
        case .openAICompatible:
            return OpenAICompatibleClient(
                baseURL: account.baseURL,
                model: account.model,
                apiKey: apiKey,
                requiresKey: true
            )
        case .ollama:
            return OpenAICompatibleClient(
                baseURL: account.baseURL,
                model: account.model,
                apiKey: apiKey,
                requiresKey: false
            )
        case .anthropic:
            return AnthropicClient(
                baseURL: account.baseURL,
                model: account.model,
                apiKey: apiKey
            )
        case .googleGemini:
            return GeminiClient(
                baseURL: account.baseURL,
                model: account.model,
                apiKey: apiKey
            )
        }
    }

    static func complete(
        messages: [ChatMessage],
        systemPrompt: String,
        store: AIAccountStore = .shared
    ) async throws -> String {
        guard let account = store.activeAccount else {
            throw AIClientError.noActiveAccount
        }
        let key = store.apiKey(for: account)
        let client = provider(for: account, apiKey: key)
        return try await client.complete(messages: messages, systemPrompt: systemPrompt)
    }

    static func testConnection(
        account: AIAccount,
        apiKey: String,
        systemPrompt: String
    ) async throws -> String {
        let client = provider(for: account, apiKey: apiKey)
        let probe = ChatMessage(role: .user, content: "Reply with exactly: ok")
        return try await client.complete(messages: [probe], systemPrompt: systemPrompt)
    }
}
