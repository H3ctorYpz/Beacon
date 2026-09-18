import Combine
import Foundation

@MainActor
final class AIAccountStore: ObservableObject {
    static let shared = AIAccountStore()

    private enum Keys {
        static let accounts = "beacon.ai.accounts"
        static let activeID = "beacon.ai.activeAccountId"
        static let migrated = "beacon.ai.migratedFromLegacy"
    }

    @Published private(set) var accounts: [AIAccount] = []
    @Published var activeAccountId: UUID? {
        didSet {
            if let activeAccountId {
                UserDefaults.standard.set(activeAccountId.uuidString, forKey: Keys.activeID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.activeID)
            }
            objectWillChange.send()
        }
    }

    var activeAccount: AIAccount? {
        guard let activeAccountId else { return accounts.first }
        return accounts.first(where: { $0.id == activeAccountId }) ?? accounts.first
    }

    private init() {
        load()
        migrateFromLegacyIfNeeded()
        if activeAccountId == nil {
            activeAccountId = accounts.first?.id
        }
    }

    func apiKey(for account: AIAccount) -> String {
        KeychainStore.load(account: keychainAccount(for: account.id)) ?? ""
    }

    func setAPIKey(_ key: String, for accountID: UUID) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = keychainAccount(for: accountID)
        if trimmed.isEmpty {
            KeychainStore.delete(account: account)
        } else {
            KeychainStore.save(account: account, secret: trimmed)
        }
        objectWillChange.send()
    }

    func add(_ account: AIAccount, apiKey: String = "") {
        accounts.append(account)
        if !apiKey.isEmpty {
            setAPIKey(apiKey, for: account.id)
        }
        if activeAccountId == nil {
            activeAccountId = account.id
        }
        save()
    }

    func update(_ account: AIAccount) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx] = account
        save()
    }

    func delete(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        KeychainStore.delete(account: keychainAccount(for: id))
        if activeAccountId == id {
            activeAccountId = accounts.first?.id
        }
        save()
    }

    func setActive(_ id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeAccountId = id
    }

    @discardableResult
    func ensurePreset(_ preset: AIAccountPreset, makeActive: Bool = true) -> AIAccount {
        let template = preset.makeAccount()
        if let idx = accounts.firstIndex(where: {
            $0.name == template.name
                || (preset == .googleGemini && $0.baseURL.contains("generativelanguage.googleapis.com"))
        }) {
            var updated = accounts[idx]
            updated.baseURL = template.baseURL
            updated.model = template.model
            updated.kind = template.kind
            if updated.name.isEmpty { updated.name = template.name }
            accounts[idx] = updated
            save()
            if makeActive { activeAccountId = updated.id }
            return updated
        }
        add(template)
        if makeActive { activeAccountId = template.id }
        return template
    }

    private func keychainAccount(for id: UUID) -> String {
        "aiAccount.\(id.uuidString)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Keys.accounts)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Keys.accounts),
              let decoded = try? JSONDecoder().decode([AIAccount].self, from: data)
        else {
            accounts = []
            return
        }
        accounts = decoded
        if let raw = UserDefaults.standard.string(forKey: Keys.activeID),
           let id = UUID(uuidString: raw) {
            activeAccountId = id
        }
    }

    private func migrateFromLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Keys.migrated) else { return }
        defaults.set(true, forKey: Keys.migrated)

        guard accounts.isEmpty else { return }

        let prefs = AppPreferences.shared
        let kind: AIAccountKind
        switch prefs.providerKind {
        case .ollama: kind = .ollama
        case .openAICompatible: kind = .openAICompatible
        }

        let account = AIAccount(
            name: kind == .ollama ? "Ollama" : "Default",
            kind: kind,
            baseURL: prefs.baseURL,
            model: prefs.model
        )
        accounts = [account]
        activeAccountId = account.id

        let legacyKey = prefs.resolvedAPIKey
        if !legacyKey.isEmpty {
            setAPIKey(legacyKey, for: account.id)
        }
        save()
    }
}
