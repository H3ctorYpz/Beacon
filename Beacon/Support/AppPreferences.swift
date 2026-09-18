import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    enum ProviderKind: String, CaseIterable, Identifiable {
        case openAICompatible
        case ollama

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openAICompatible: return "OpenAI-compatible"
            case .ollama: return "Ollama (local)"
            }
        }
    }

    enum IslandEdge: String, CaseIterable, Identifiable {
        case top, bottom, leading, trailing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .top: return "Top"
            case .bottom: return "Bottom"
            case .leading: return "Left"
            case .trailing: return "Right"
            }
        }

        var icon: String {
            switch self {
            case .top: return "rectangle.topthird.inset.filled"
            case .bottom: return "rectangle.bottomthird.inset.filled"
            case .leading: return "rectangle.lefthalf.inset.filled"
            case .trailing: return "rectangle.righthalf.inset.filled"
            }
        }
    }

    /// Speech-to-text locale. This is transcription, not translation.
    enum DictationLanguage: String, CaseIterable, Identifiable {
        case auto
        case esMX, esES, esUS
        case enUS, enGB
        case ptBR, frFR, deDE, itIT
        case jaJP, zhCN, koKR

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: return "Auto (system languages)"
            case .esMX: return "Español (México)"
            case .esES: return "Español (España)"
            case .esUS: return "Español (Estados Unidos)"
            case .enUS: return "English (US)"
            case .enGB: return "English (UK)"
            case .ptBR: return "Português (Brasil)"
            case .frFR: return "Français"
            case .deDE: return "Deutsch"
            case .itIT: return "Italiano"
            case .jaJP: return "日本語"
            case .zhCN: return "中文 (简体)"
            case .koKR: return "한국어"
            }
        }

        var localeIdentifier: String? {
            switch self {
            case .auto: return nil
            case .esMX: return "es-MX"
            case .esES: return "es-ES"
            case .esUS: return "es-US"
            case .enUS: return "en-US"
            case .enGB: return "en-GB"
            case .ptBR: return "pt-BR"
            case .frFR: return "fr-FR"
            case .deDE: return "de-DE"
            case .itIT: return "it-IT"
            case .jaJP: return "ja-JP"
            case .zhCN: return "zh-CN"
            case .koKR: return "ko-KR"
            }
        }
    }

    private enum Keys {
        static let provider = "beacon.provider"
        static let baseURL = "beacon.baseURL"
        static let model = "beacon.model"
        static let systemPrompt = "beacon.systemPrompt"
        static let launchAtLogin = "beacon.launchAtLogin"
        static let showDockIcon = "beacon.showDockIcon"
        static let islandEdge = "beacon.islandEdge"
        static let islandOffsetX = "beacon.islandOffsetX"
        static let islandOffsetY = "beacon.islandOffsetY"
        static let islandMaxWidth = "beacon.islandMaxWidth"
        static let expandOnHover = "beacon.expandOnHover"
        static let autoHideSeconds = "beacon.autoHideSeconds"
        static let showModelChip = "beacon.showModelChip"
        static let dictationLanguage = "beacon.dictationLanguage"
        static let agentModeEnabled = "beacon.agentModeEnabled"
        static let pillVisibleOnLaunch = "beacon.pillVisibleOnLaunch"
    }

    private let defaults = UserDefaults.standard
    private let apiKeyAccount = "apiKey"

    @Published var providerKind: ProviderKind {
        didSet { defaults.set(providerKind.rawValue, forKey: Keys.provider) }
    }

    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Keys.baseURL) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    @Published var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: Keys.systemPrompt) }
    }

    @Published var apiKeyDraft: String = "" {
        didSet {
            let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                KeychainStore.delete(account: apiKeyAccount)
            } else {
                KeychainStore.save(account: apiKeyAccount, secret: trimmed)
            }
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLoginItem()
        }
    }

    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        }
    }

    /// Where the island docks on the screen.
    @Published var islandEdge: IslandEdge {
        didSet {
            defaults.set(islandEdge.rawValue, forKey: Keys.islandEdge)
            notifyPlacementChanged()
        }
    }

    /// Fine nudge in points. +X = right, +Y = up.
    @Published var islandOffsetX: Double {
        didSet {
            defaults.set(islandOffsetX, forKey: Keys.islandOffsetX)
            notifyPlacementChanged()
        }
    }

    @Published var islandOffsetY: Double {
        didSet {
            defaults.set(islandOffsetY, forKey: Keys.islandOffsetY)
            notifyPlacementChanged()
        }
    }

    /// Max width when expanded — iPhone-like, not full display.
    @Published var islandMaxWidth: Double {
        didSet {
            defaults.set(islandMaxWidth, forKey: Keys.islandMaxWidth)
            notifyPlacementChanged()
        }
    }

    /// Expand when the pointer enters the collapsed pill.
    @Published var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: Keys.expandOnHover) }
    }

    /// Seconds of idle (no hover / typing / sending) before auto-collapse. 0 = never.
    @Published var autoHideSeconds: Double {
        didSet { defaults.set(autoHideSeconds, forKey: Keys.autoHideSeconds) }
    }

    /// Show the active model name under the expanded island.
    @Published var showModelChip: Bool {
        didSet { defaults.set(showModelChip, forKey: Keys.showModelChip) }
    }

    /// Locale used for microphone dictation (speech → text, not translation).
    @Published var dictationLanguage: DictationLanguage {
        didSet { defaults.set(dictationLanguage.rawValue, forKey: Keys.dictationLanguage) }
    }

    /// Allow the model to request Mac tools (files, terminal, etc.) with user approval.
    @Published var agentModeEnabled: Bool {
        didSet { defaults.set(agentModeEnabled, forKey: Keys.agentModeEnabled) }
    }

    /// Whether the island pill should be shown (persists hide/show).
    @Published var pillVisibleOnLaunch: Bool {
        didSet { defaults.set(pillVisibleOnLaunch, forKey: Keys.pillVisibleOnLaunch) }
    }

    var resolvedAPIKey: String {
        KeychainStore.load(account: apiKeyAccount) ?? ""
    }

    private init() {
        let storedProvider = defaults.string(forKey: Keys.provider) ?? ProviderKind.openAICompatible.rawValue
        providerKind = ProviderKind(rawValue: storedProvider) ?? .openAICompatible
        baseURL = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        model = defaults.string(forKey: Keys.model) ?? "gpt-4o-mini"
        systemPrompt = defaults.string(forKey: Keys.systemPrompt)
            ?? "You are Beacon, a concise macOS assistant with optional Mac tools. Answer clearly in the user's language. When tools are enabled and needed, use beacon_tools JSON; otherwise reply in plain text."
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? true
        apiKeyDraft = KeychainStore.load(account: apiKeyAccount) ?? ""

        let edgeRaw = defaults.string(forKey: Keys.islandEdge) ?? IslandEdge.top.rawValue
        islandEdge = IslandEdge(rawValue: edgeRaw) ?? .top
        islandOffsetX = defaults.object(forKey: Keys.islandOffsetX) as? Double ?? 0
        islandOffsetY = defaults.object(forKey: Keys.islandOffsetY) as? Double ?? 0
        islandMaxWidth = defaults.object(forKey: Keys.islandMaxWidth) as? Double ?? 360
        expandOnHover = defaults.object(forKey: Keys.expandOnHover) as? Bool ?? true
        autoHideSeconds = defaults.object(forKey: Keys.autoHideSeconds) as? Double ?? 8
        showModelChip = defaults.object(forKey: Keys.showModelChip) as? Bool ?? false
        let dictationRaw = defaults.string(forKey: Keys.dictationLanguage) ?? DictationLanguage.esMX.rawValue
        dictationLanguage = DictationLanguage(rawValue: dictationRaw) ?? .esMX
        agentModeEnabled = defaults.object(forKey: Keys.agentModeEnabled) as? Bool ?? true
        pillVisibleOnLaunch = defaults.object(forKey: Keys.pillVisibleOnLaunch) as? Bool ?? true
    }

    func resetIslandPlacement() {
        islandEdge = .top
        islandOffsetX = 0
        islandOffsetY = 0
        islandMaxWidth = 360
        expandOnHover = true
        autoHideSeconds = 8
    }

    func applyProviderDefaults() {
        switch providerKind {
        case .openAICompatible:
            if baseURL.contains("11434") || baseURL.isEmpty {
                baseURL = "https://api.openai.com/v1"
            }
            if model == "llama3.2" {
                model = "gpt-4o-mini"
            }
        case .ollama:
            baseURL = "http://127.0.0.1:11434/v1"
            if model.hasPrefix("gpt-") {
                model = "llama3.2"
            }
        }
    }

    private func notifyPlacementChanged() {
        NotificationCenter.default.post(name: .beaconIslandPlacementChanged, object: nil)
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {}
    }
}

extension Notification.Name {
    static let beaconIslandPlacementChanged = Notification.Name("beaconIslandPlacementChanged")
    static let beaconPillVisibilityPreferenceChanged = Notification.Name("beaconPillVisibilityPreferenceChanged")
}
