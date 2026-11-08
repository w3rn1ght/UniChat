import Foundation

enum ProviderKind: String, Codable {
    case openAICompatible
    case gemini

    var title: String {
        switch self {
        case .openAICompatible: return "OpenAI-совместимый"
        case .gemini: return "Google Gemini"
        }
    }

    var shortTitle: String {
        switch self {
        case .openAICompatible: return "OpenAI API"
        case .gemini: return "Gemini API"
        }
    }
}

/// Настройки одного провайдера. API-ключ лежит в Keychain.
struct ProviderConfig: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: ProviderKind
    var baseURL: String
    var model: String
    var modelPresets: [String]
    var extraHeaders: [String: String]
    var systemPrompt: String

    init(id: UUID = UUID(),
         name: String,
         kind: ProviderKind,
         baseURL: String,
         model: String,
         modelPresets: [String] = [],
         extraHeaders: [String: String] = [:],
         systemPrompt: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.modelPresets = modelPresets
        self.extraHeaders = extraHeaders
        self.systemPrompt = systemPrompt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, baseURL, model, modelPresets, extraHeaders, systemPrompt
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
    }

    var keychainAccount: String {
        return "provider." + id.uuidString
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

    var trimmedAPIKey: String {
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBaseURL: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    var hasAPIKey: Bool {
        return !trimmedAPIKey.isEmpty
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

    private(set) var providers: [ProviderConfig] = []

    private init() {}

    func load() {
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providers = stored
        }
        if providers.isEmpty {
            providers = AppSettings.makeDefaultProviders()
            persist()
        }
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

    // MARK: - Провайдеры по умолчанию

    static func makeDefaultProviders() -> [ProviderConfig] {
        return [
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
                name: "DeepSeek",
                kind: .openAICompatible,
                baseURL: "https://api.deepseek.com/v1",
                model: "deepseek-chat",
                modelPresets: ["deepseek-chat", "deepseek-reasoner"]
            ),
            ProviderConfig(
                name: "Gemini",
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
