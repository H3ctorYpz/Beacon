import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum AIClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case badStatus(Int, String)
    case emptyResponse
    case transport(String)
    case noActiveAccount

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an API key in Settings › AI."
        case .invalidURL:
            return "The API base URL is invalid."
        case .badStatus(let code, let body):
            if body.localizedCaseInsensitiveContains("no longer available") {
                return "Este modelo ya no está disponible para keys nuevas. Cambia a gemini-3.5-flash o gemini-3.8-flash."
            }
            return "Server error \(code): \(body)"
        case .emptyResponse:
            return "The model returned an empty reply."
        case .transport(let message):
            return message
        case .noActiveAccount:
            return "Add an AI account in Settings › AI."
        }
    }
}

enum AIAccountKind: String, Codable, CaseIterable, Identifiable {
    case openAICompatible
    case anthropic
    case ollama
    case googleGemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible: return "OpenAI-compatible"
        case .anthropic: return "Anthropic"
        case .ollama: return "Ollama"
        case .googleGemini: return "Google Gemini"
        }
    }

    var needsAPIKey: Bool {
        switch self {
        case .ollama: return false
        case .openAICompatible, .anthropic, .googleGemini: return true
        }
    }
}

struct AIAccount: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var kind: AIAccountKind
    var baseURL: String
    var model: String

    init(
        id: UUID = UUID(),
        name: String,
        kind: AIAccountKind,
        baseURL: String,
        model: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
    }

    var shortLabel: String {
        let m = model
        if m.count <= 22 { return m }
        return String(m.prefix(20)) + "…"
    }
}

enum AIAccountPreset: String, CaseIterable, Identifiable {
    // Frontier labs
    case openAI, anthropic, googleGemini, xAI, mistral, deepSeek, moonshot, cohere
    // Aggregators / gateways
    case openRouter, vercelAIGateway, githubModels
    // Fast inference hosts
    case groq, together, fireworks, perplexity, cerebras, sambaNova, deepInfra, nebius, novita
    case siliconFlow, nvidiaNIM, huggingface
    // Asia / regional OpenAI-compatible
    case dashScope, zhipu, minimax
    // Local / self-host
    case ollama, lmStudio, localOpenAI
    // Bring your own
    case azureOpenAI, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        case .googleGemini: return "Google Gemini"
        case .xAI: return "xAI (Grok)"
        case .mistral: return "Mistral"
        case .deepSeek: return "DeepSeek"
        case .moonshot: return "Moonshot (Kimi)"
        case .cohere: return "Cohere"
        case .openRouter: return "OpenRouter"
        case .vercelAIGateway: return "Vercel AI Gateway"
        case .githubModels: return "GitHub Models"
        case .groq: return "Groq"
        case .together: return "Together AI"
        case .fireworks: return "Fireworks"
        case .perplexity: return "Perplexity"
        case .cerebras: return "Cerebras"
        case .sambaNova: return "SambaNova"
        case .deepInfra: return "DeepInfra"
        case .nebius: return "Nebius"
        case .novita: return "Novita"
        case .siliconFlow: return "SiliconFlow"
        case .nvidiaNIM: return "NVIDIA NIM"
        case .huggingface: return "Hugging Face"
        case .dashScope: return "Alibaba DashScope (Qwen)"
        case .zhipu: return "Zhipu (GLM)"
        case .minimax: return "MiniMax"
        case .ollama: return "Ollama (local)"
        case .lmStudio: return "LM Studio (local)"
        case .localOpenAI: return "Local OpenAI-compatible"
        case .azureOpenAI: return "Azure OpenAI"
        case .custom: return "Custom OpenAI-compatible"
        }
    }

    var group: String {
        switch self {
        case .openAI, .anthropic, .googleGemini, .xAI, .mistral, .deepSeek, .moonshot, .cohere:
            return "Labs"
        case .openRouter, .vercelAIGateway, .githubModels:
            return "Gateways"
        case .groq, .together, .fireworks, .perplexity, .cerebras, .sambaNova, .deepInfra, .nebius, .novita, .siliconFlow, .nvidiaNIM, .huggingface:
            return "Inference hosts"
        case .dashScope, .zhipu, .minimax:
            return "Regional"
        case .ollama, .lmStudio, .localOpenAI:
            return "Local"
        case .azureOpenAI, .custom:
            return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .anthropic: return "Messages API · console key"
        case .ollama, .lmStudio, .localOpenAI: return "Usually no API key"
        case .azureOpenAI: return "Paste your Azure resource URL"
        case .custom: return "Any …/v1 endpoint"
        default: return "OpenAI-compatible · API key"
        }
    }

    func makeAccount() -> AIAccount {
        switch self {
        case .openAI:
            return AIAccount(name: "OpenAI", kind: .openAICompatible, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini")
        case .anthropic:
            return AIAccount(name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-20250514")
        case .googleGemini:
            return AIAccount(
                name: "Google Gemini",
                kind: .googleGemini,
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                // 2.5-flash returns 404 for new API keys ("no longer available to new users").
                model: "gemini-3.5-flash"
            )        case .xAI:
            return AIAccount(name: "xAI", kind: .openAICompatible, baseURL: "https://api.x.ai/v1", model: "grok-2-latest")
        case .mistral:
            return AIAccount(name: "Mistral", kind: .openAICompatible, baseURL: "https://api.mistral.ai/v1", model: "mistral-small-latest")
        case .deepSeek:
            return AIAccount(name: "DeepSeek", kind: .openAICompatible, baseURL: "https://api.deepseek.com", model: "deepseek-chat")
        case .moonshot:
            return AIAccount(name: "Moonshot", kind: .openAICompatible, baseURL: "https://api.moonshot.ai/v1", model: "moonshot-v1-auto")
        case .cohere:
            return AIAccount(name: "Cohere", kind: .openAICompatible, baseURL: "https://api.cohere.ai/compatibility/v1", model: "command-r-plus")
        case .openRouter:
            return AIAccount(name: "OpenRouter", kind: .openAICompatible, baseURL: "https://openrouter.ai/api/v1", model: "openai/gpt-4o-mini")
        case .vercelAIGateway:
            return AIAccount(name: "Vercel AI Gateway", kind: .openAICompatible, baseURL: "https://ai-gateway.vercel.sh/v1", model: "openai/gpt-4o-mini")
        case .githubModels:
            return AIAccount(name: "GitHub Models", kind: .openAICompatible, baseURL: "https://models.inference.ai.azure.com", model: "gpt-4o-mini")
        case .groq:
            return AIAccount(name: "Groq", kind: .openAICompatible, baseURL: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile")
        case .together:
            return AIAccount(name: "Together AI", kind: .openAICompatible, baseURL: "https://api.together.xyz/v1", model: "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo")
        case .fireworks:
            return AIAccount(name: "Fireworks", kind: .openAICompatible, baseURL: "https://api.fireworks.ai/inference/v1", model: "accounts/fireworks/models/llama-v3p1-70b-instruct")
        case .perplexity:
            return AIAccount(name: "Perplexity", kind: .openAICompatible, baseURL: "https://api.perplexity.ai", model: "sonar")
        case .cerebras:
            return AIAccount(name: "Cerebras", kind: .openAICompatible, baseURL: "https://api.cerebras.ai/v1", model: "llama-3.3-70b")
        case .sambaNova:
            return AIAccount(name: "SambaNova", kind: .openAICompatible, baseURL: "https://api.sambanova.ai/v1", model: "Meta-Llama-3.3-70B-Instruct")
        case .deepInfra:
            return AIAccount(name: "DeepInfra", kind: .openAICompatible, baseURL: "https://api.deepinfra.com/v1/openai", model: "meta-llama/Meta-Llama-3.1-70B-Instruct")
        case .nebius:
            return AIAccount(name: "Nebius", kind: .openAICompatible, baseURL: "https://api.studio.nebius.ai/v1", model: "meta-llama/Meta-Llama-3.1-70B-Instruct")
        case .novita:
            return AIAccount(name: "Novita", kind: .openAICompatible, baseURL: "https://api.novita.ai/v3/openai", model: "meta-llama/llama-3.1-70b-instruct")
        case .siliconFlow:
            return AIAccount(name: "SiliconFlow", kind: .openAICompatible, baseURL: "https://api.siliconflow.cn/v1", model: "deepseek-ai/DeepSeek-V3")
        case .nvidiaNIM:
            return AIAccount(name: "NVIDIA NIM", kind: .openAICompatible, baseURL: "https://integrate.api.nvidia.com/v1", model: "meta/llama-3.1-70b-instruct")
        case .huggingface:
            return AIAccount(name: "Hugging Face", kind: .openAICompatible, baseURL: "https://router.huggingface.co/v1", model: "meta-llama/Meta-Llama-3.1-70B-Instruct")
        case .dashScope:
            return AIAccount(name: "DashScope", kind: .openAICompatible, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus")
        case .zhipu:
            return AIAccount(name: "Zhipu", kind: .openAICompatible, baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash")
        case .minimax:
            return AIAccount(name: "MiniMax", kind: .openAICompatible, baseURL: "https://api.minimax.chat/v1", model: "MiniMax-Text-01")
        case .ollama:
            return AIAccount(name: "Ollama", kind: .ollama, baseURL: "http://127.0.0.1:11434/v1", model: "llama3.2")
        case .lmStudio:
            return AIAccount(name: "LM Studio", kind: .ollama, baseURL: "http://127.0.0.1:1234/v1", model: "local-model")
        case .localOpenAI:
            return AIAccount(name: "Local", kind: .ollama, baseURL: "http://127.0.0.1:8080/v1", model: "local-model")
        case .azureOpenAI:
            return AIAccount(name: "Azure OpenAI", kind: .openAICompatible, baseURL: "https://YOUR_RESOURCE.openai.azure.com/openai/deployments/YOUR_DEPLOYMENT", model: "gpt-4o-mini")
        case .custom:
            return AIAccount(name: "Custom", kind: .openAICompatible, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini")
        }
    }

    static var grouped: [(String, [AIAccountPreset])] {
        let order = ["Labs", "Gateways", "Inference hosts", "Regional", "Local", "Custom"]
        let map = Dictionary(grouping: allCases, by: \.group)
        return order.compactMap { key in
            guard let items = map[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }
}

protocol AIProviding {
    func complete(messages: [ChatMessage], systemPrompt: String) async throws -> String
}

enum AIHTTP {
    static func friendlyBody(_ text: String) -> String {
        let clipped = String(text.prefix(280))
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return clipped }

        if let dict = json as? [String: Any] {
            if let err = dict["error"] as? [String: Any] {
                if let message = err["message"] as? String { return message }
                if let status = err["status"] as? String, let code = err["code"] {
                    return "\(status) (\(code))"
                }
            }
            if let message = dict["message"] as? String { return message }
        }
        if let arr = json as? [[String: Any]], let first = arr.first,
           let err = first["error"] as? [String: Any],
           let message = err["message"] as? String {
            return message
        }
        return clipped
    }
}
