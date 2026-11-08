import Foundation

/// Gemini через обычный веб-аккаунт gemini.google.com.
///
/// Запросы выполняются внутри залогиненного WKWebView: так WebKit сам
/// отправляет cookie Google, включая HttpOnly-сессии, которые недоступны
/// обычному URLSession.
final class GeminiAccountProvider: ChatProvider {

    let config: ProviderConfig

    init(config: ProviderConfig) {
        self.config = config
    }

    private var ready: Bool {
        return config.accountConnected
    }

    func streamChat(_ chat: ChatRequest,
                    onDelta: @escaping (String) -> Void,
                    onFinish: @escaping (Error?) -> Void) -> CancellableTask? {

        guard ready else {
            onFinish(ChatError(message: "Войдите в аккаунт Gemini в настройках провайдера."))
            return nil
        }

        let prompt = AccountPrompt.build(chat)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onFinish(ChatError(message: "Пустой запрос к Gemini."))
            return nil
        }

        let rawModel = chat.model.isEmpty ? config.model : chat.model
        let model = GeminiModelOption.from(rawModel)

        return GeminiWebSession.shared.stream(prompt: prompt,
                                              model: model,
                                              onDelta: onDelta,
                                              onFinish: onFinish)
    }

    func testConnection(completion: @escaping (Result<String, Error>) -> Void) {
        guard ready else {
            completion(.failure(ChatError(message: "Войдите в аккаунт Gemini.")))
            return
        }

        GeminiWebSession.shared.testConnection { result in
            switch result {
            case .success(let message):
                DispatchQueue.main.async {
                    if var current = AppSettings.shared.provider(id: self.config.id) {
                        current.accountConnected = true
                        AppSettings.shared.upsert(current)
                    }
                    completion(.success(message))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
