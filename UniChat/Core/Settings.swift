import Foundation

enum ProviderKind: String, Codable {
    case openAICompatible
    case gemini
    case deepSeekAccount
    case geminiAccount

    var title: String {
        switch self {
        case .openAICompatible: return "OpenAI-совместимый"
        case .gemini: return "Google Gemini (API-ключ)"
        case .deepSeekAccount: return "DeepSeek (вход в аккаунт)"
        case .geminiAccount: return "Gemini (вход в аккаунт)"
        }
    }

    var shortTitle: String {
        switch self {
        case .openAICompatible: return "OpenAI API"
        case .gemini: return "Gemini API"
        case .deepSeekAccount: return "DeepSeek аккаунт"
        case .geminiAccount: return "Gemini аккаунт"
        }
    }

    var isAccount: Bool {
        return self == .deepSeekAccount || self == .geminiAccount
    }
}

/// Настройки одного провайдера. API-ключ и токен аккаунта лежат в Keychain.
struct ProviderConfig: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: ProviderKind
    var baseURL: String
    var model: String
    var modelPresets: [String]
    var extraHeaders: [String: String]
    var systemPrompt: String
    var accountConnected: Bool
    var accountEmail: String

    init(id: UUID = UUID(),
         name: String,
         kind: ProviderKind,
         baseURL: String,
         model: String,
         modelPresets: [String] = [],
         extraHeaders: [String: String] = [:],
         systemPrompt: String = "",
         accountConnected: Bool = false,
         accountEmail: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.modelPresets = modelPresets
        self.extraHeaders = extraHeaders
        self.systemPrompt = systemPrompt
        self.accountConnected = accountConnected
        self.accountEmail = accountEmail
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, baseURL, model, modelPresets, extraHeaders, systemPrompt,
             accountConnected, accountEmail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Провайдер"
        kind = try container.decodeIfPresent(ProviderKind.self, forKey: .kind) ?? .openAICompatible
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        modelPresets = try container.decodeIfPresent([String].self, forKey: .modelPresets) ?? []
        extraHeaders = try container.decodeIfPresent([String: String].self, forKey: .extraHeaders) ?? [:]
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        accountConnected = try container.decodeIfPresent(Bool.self, forKey: .accountConnected) ?? false
        accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail) ?? ""
    }

    var keychainAccount: String {
        return "provider." + id.uuidString
    }

    var accountTokenKeychainAccount: String {
        return "account." + id.uuidString
    }

    var apiKey: String {
        get { return Keychain.get(account: keychainAccount) ?? "" }
        set {
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Keychain.delete(account: keychainAccount)
            } else {
                Keychain.set(newValue, account: keychainAccount)
            }
        }
    }

    var accountToken: String {
        get { return Keychain.get(account: accountTokenKeychainAccount) ?? "" }
        set {
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Keychain.delete(account: accountTokenKeychainAccount)
            } else {
                Keychain.set(newValue, account: accountTokenKeychainAccount)
            }
        }
    }

    var trimmedAPIKey: String {
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAccountToken: String {
        return accountToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBaseURL: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    var hasAPIKey: Bool {
        return !trimmedAPIKey.isEmpty
    }

    /// Готов ли провайдер к запросу: ключ для API или активная сессия аккаунта.
    var isReady: Bool {
        switch kind {
        case .deepSeekAccount:
            return !trimmedAccountToken.isEmpty
        case .geminiAccount:
            return accountConnected
        default:
            return hasAPIKey
        }
    }

    var accountStatusText: String {
        if kind == .deepSeekAccount {
            if !trimmedAccountToken.isEmpty {
                return accountEmail.isEmpty ? "Аккаунт подключён" : accountEmail
            }
            return "Войти в аккаунт"
        }
        if kind == .geminiAccount {
            if accountConnected {
                return accountEmail.isEmpty ? "Аккаунт подключён" : accountEmail
            }
            return "Войти в аккаунт"
        }
        return hasAPIKey ? "Ключ сохранён" : "Нет API-ключа"
    }
}

/// Глобальные настройки приложения: список провайдеров и последний выбор.
final class AppSettings {

    static let shared = AppSettings()
    static let didChangeNotification = Notification.Name("UniChatSettingsDidChange")

    private let defaults = UserDefaults.standard
    private let storageKey = "unichat.providers.v1"
    private let lastProviderKey = "unichat.lastProviderID"
    private let lastModelPrefix = "unichat.lastModel."
    private let restoreAnyModelKey = "unichat.migration.restoreAnyModel.v1"
    private let recentModelsKey = "unichat.recentModels.v1"
    private let recentModelsLimit = 8

    /// Недавно выбранная модель в связке с провайдером.
    struct RecentModel {
        let providerID: UUID
        let model: String
    }

    private(set) var providers: [ProviderConfig] = []

    private init() {}

    func load() {
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providers = stored
        }
        if providers.isEmpty {
            providers = AppSettings.makeDefaultProviders()
            defaults.set(true, forKey: restoreAnyModelKey)
            persist()
            return
        }
        migrateProviderList()
        restoreAnyModelIfNeeded()
    }

    /// Возвращает случайно удалённый провайдер AnyModel (один раз на установку).
    private func restoreAnyModelIfNeeded() {
        if defaults.bool(forKey: restoreAnyModelKey) { return }
        defaults.set(true, forKey: restoreAnyModelKey)

        let alreadyPresent = providers.contains { provider in
            return provider.baseURL.lowercased().contains("anymodel.org")
                || provider.name.lowercased().contains("anymodel")
        }
        guard !alreadyPresent else { return }

        providers.append(ProviderConfig(
            name: "AnyModel",
            kind: .openAICompatible,
            baseURL: "https://anymodel.org/v1",
            model: "deepseek-chat",
            modelPresets: [
                "deepseek-chat",
                "deepseek-reasoner",
                "gemini-2.5-flash",
                "gpt-5",
                "claude-sonnet-4"
            ]
        ))
        persist()
    }

    /// Добавляет новые режимы аккаунтов в уже существующий список провайдеров.
    private func migrateProviderList() {
        var changed = false

        if !providers.contains(where: { $0.kind == .deepSeekAccount }) {
            providers.append(ProviderConfig(
                name: "DeepSeek (аккаунт)",
                kind: .deepSeekAccount,
                baseURL: "https://chat.deepseek.com",
                model: "deepseek-chat",
                modelPresets: ["deepseek-chat", "deepseek-reasoner"]
            ))
            changed = true
        }

        if !providers.contains(where: { $0.kind == .geminiAccount }) {
            providers.append(ProviderConfig(
                name: "Gemini (аккаунт)",
                kind: .geminiAccount,
                baseURL: "https://gemini.google.com",
                model: "gemini-flash",
                modelPresets: ["gemini-flash", "gemini-pro", "gemini-flash-lite", "auto"]
            ))
            changed = true
        }

        if changed { persist() }
    }

    func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(providers) {
            defaults.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: nil)
    }

    func provider(id: UUID?) -> ProviderConfig? {
        guard let id = id else { return nil }
        return providers.first { $0.id == id }
    }

    func firstProvider() -> ProviderConfig? {
        return providers.first
    }

    func upsert(_ provider: ProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        persist()
    }

    func remove(id: UUID) {
        providers.removeAll { $0.id == id }
        Keychain.delete(account: "provider." + id.uuidString)
        Keychain.delete(account: "account." + id.uuidString)
        pruneRecentModels(for: id)
        if lastProviderID == id {
            lastProviderID = providers.first?.id
        }
        persist()
    }

    var lastProviderID: UUID? {
        get {
            guard let raw = defaults.string(forKey: lastProviderKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let value = newValue {
                defaults.set(value.uuidString, forKey: lastProviderKey)
            } else {
                defaults.removeObject(forKey: lastProviderKey)
            }
        }
    }

    func lastModel(for providerID: UUID) -> String? {
        return defaults.string(forKey: lastModelPrefix + providerID.uuidString)
    }

    func setLastModel(_ model: String, for providerID: UUID) {
        defaults.set(model, forKey: lastModelPrefix + providerID.uuidString)
    }

    // MARK: - Недавние модели

    func recentModels() -> [RecentModel] {
        guard let stored = defaults.array(forKey: recentModelsKey) as? [String] else {
            return []
        }
        var result: [RecentModel] = []
        for item in stored {
            let parts = item.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let providerID = UUID(uuidString: parts[0]),
                  !parts[1].isEmpty else { continue }
            result.append(RecentModel(providerID: providerID, model: parts[1]))
        }
        return result
    }

    func addRecentModel(_ model: String, providerID: UUID) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let value = providerID.uuidString + "|" + trimmed
        var items = (defaults.array(forKey: recentModelsKey) as? [String]) ?? []
        items.removeAll { $0 == value }
        items.insert(value, at: 0)
        if items.count > recentModelsLimit {
            items = Array(items.prefix(recentModelsLimit))
        }
        defaults.set(items, forKey: recentModelsKey)
    }

    private func pruneRecentModels(for providerID: UUID) {
        guard let items = defaults.array(forKey: recentModelsKey) as? [String] else { return }
        let prefix = providerID.uuidString + "|"
        defaults.set(items.filter { !$0.hasPrefix(prefix) }, forKey: recentModelsKey)
    }

    // MARK: - Провайдеры по умолчанию

    static func makeDefaultProviders() -> [ProviderConfig] {
        return [
            ProviderConfig(
                name: "DeepSeek (аккаунт)",
                kind: .deepSeekAccount,
                baseURL: "https://chat.deepseek.com",
                model: "deepseek-chat",
                modelPresets: ["deepseek-chat", "deepseek-reasoner"]
            ),
            ProviderConfig(
                name: "Gemini (аккаунт)",
                kind: .geminiAccount,
                baseURL: "https://gemini.google.com",
                model: "gemini-flash",
                modelPresets: ["gemini-flash", "gemini-pro", "gemini-flash-lite", "auto"]
            ),
            ProviderConfig(
                name: "OpenRouter",
                kind: .openAICompatible,
                baseURL: "https://openrouter.ai/api/v1",
                model: "deepseek/deepseek-chat-v3-0324:free",
                modelPresets: [
                    "deepseek/deepseek-chat-v3-0324:free",
                    "deepseek/deepseek-r1:free",
                    "google/gemini-2.0-flash-exp:free",
                    "meta-llama/llama-3.3-70b-instruct:free"
                ],
                extraHeaders: [
                    "HTTP-Referer": "https://unichat.local",
                    "X-Title": "UniChat"
                ]
            ),
            ProviderConfig(
                name: "AnyModel",
                kind: .openAICompatible,
                baseURL: "https://anymodel.org/v1",
                model: "deepseek-chat",
                modelPresets: [
                    "deepseek-chat",
                    "deepseek-reasoner",
                    "gemini-2.5-flash",
                    "gpt-5",
                    "claude-sonnet-4"
                ]
            ),
            ProviderConfig(
                name: "DeepSeek API",
                kind: .openAICompatible,
                baseURL: "https://api.deepseek.com/v1",
                model: "deepseek-chat",
                modelPresets: ["deepseek-chat", "deepseek-reasoner"]
            ),
            ProviderConfig(
                name: "Gemini API",
                kind: .gemini,
                baseURL: "https://generativelanguage.googleapis.com",
                model: "gemini-2.5-flash",
                modelPresets: [
                    "gemini-2.5-flash",
                    "gemini-2.5-pro",
                    "gemini-2.0-flash",
                    "gemini-2.0-flash-lite"
                ]
            ),
            ProviderConfig(
                name: "Gemini через релей (РФ)",
                kind: .gemini,
                baseURL: "https://your-gemini-relay.workers.dev",
                model: "gemini-2.5-flash",
                modelPresets: [
                    "gemini-2.5-flash",
                    "gemini-2.5-pro",
                    "gemini-2.0-flash"
                ],
                systemPrompt: ""
            )
        ]
    }
}
