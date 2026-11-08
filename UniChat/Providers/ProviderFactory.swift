import Foundation

enum ProviderFactory {

    static func make(for config: ProviderConfig) -> ChatProvider {
        switch config.kind {
        case .openAICompatible:
            return OpenAICompatibleProvider(config: config)
        case .gemini:
            return GeminiProvider(config: config)
        case .deepSeekAccount:
            return DeepSeekAccountProvider(config: config)
        case .geminiAccount:
            return GeminiAccountProvider(config: config)
        }
    }
}
