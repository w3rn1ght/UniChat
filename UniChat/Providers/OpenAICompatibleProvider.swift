import Foundation

/// Провайдер с OpenAI-совместимым API: OpenRouter, AnyModel, DeepSeek и другие.
final class OpenAICompatibleProvider: ChatProvider {

    let config: ProviderConfig

    init(config: ProviderConfig) {
        self.config = config
    }

    private var endpoint: URL? {
        return URL(string: config.normalizedBaseURL + "/chat/completions")
    }

    private var headers: [String: String] {
        var result: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "Authorization": "Bearer " + config.trimmedAPIKey
        ]
        for (key, value) in config.extraHeaders where !key.isEmpty {
            result[key] = value
        }
        return result
    }

    // MARK: - Chat

    func streamChat(_ chat: ChatRequest,
                    onDelta: @escaping (String) -> Void,
                    onFinish: @escaping (Error?) -> Void) -> CancellableTask? {

        guard let url = endpoint, url.scheme != nil else {
            onFinish(ChatError(message: "Некорректный Base URL: «\(config.baseURL)»."))
            return nil
        }
        guard config.hasAPIKey else {
            onFinish(ChatError(message: "Не задан API-ключ для «\(config.name)».\nОткройте Настройки → \(config.name)."))
            return nil
        }

        let model = chat.model.isEmpty ? config.model : chat.model
        guard !model.isEmpty else {
            onFinish(ChatError(message: "Не задана модель для «\(config.name)»."))
            return nil
        }

        var messages: [[String: Any]] = []
        if !chat.resolvedSystemPrompt.isEmpty {
            messages.append(["role": "system", "content": chat.resolvedSystemPrompt])
        }
        for message in chat.usableMessages {
            let role = message.role == .assistant ? "assistant" : "user"
            messages.append(["role": role, "content": message.text])
        }
        guard !messages.isEmpty else {
            onFinish(ChatError(message: "Пустой запрос."))
            return nil
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages
        ]
        if let temperature = chat.temperature {
            body["temperature"] = temperature
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            onFinish(ChatError(message: "Не удалось собрать JSON запроса."))
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let session = StreamingSession()
        var finished = false
        var streamError: ChatError?

        let finishOnce: (Error?) -> Void = { error in
            guard !finished else { return }
            finished = true
            let finalError = error ?? streamError
            DispatchQueue.main.async {
                onFinish(finalError)
            }
        }

        let emit: (String) -> Void = { text in
            DispatchQueue.main.async {
                onDelta(text)
            }
        }

        session.start(request: request, onEvent: { payload in
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "[DONE]" {
                finishOnce(nil)
                return
            }

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []),
                  let object = json as? [String: Any] else {
                return
            }

            if let errorObject = object["error"] {
                if let dictionary = errorObject as? [String: Any] {
                    let message = dictionary["message"] as? String
                    let code = dictionary["code"].map { "\($0)" } ?? ""
                    let detail = message ?? (code.isEmpty ? "неизвестная ошибка" : code)
                    streamError = ChatError(message: "Провайдер: " + detail)
                } else if let text = errorObject as? String {
                    streamError = ChatError(message: "Провайдер: " + text)
                }
                return
            }

            guard let choices = object["choices"] as? [[String: Any]],
                  let first = choices.first else { return }

            if let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String,
               !content.isEmpty {
                emit(content)
                return
            }

            if let message = first["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                emit(content)
                return
            }

            if let text = first["text"] as? String, !text.isEmpty {
                emit(text)
            }
        }, onFinish: { error in
            finishOnce(error)
        })

        return session
    }

    // MARK: - Проверка

    func testConnection(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = endpoint, url.scheme != nil else {
            completion(.failure(ChatError(message: "Некорректный Base URL.")))
            return
        }
        guard config.hasAPIKey else {
            completion(.failure(ChatError(message: "Не задан API-ключ.")))
            return
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1,
            "stream": false
        ]
        if config.model.isEmpty { body.removeValue(forKey: "model") }

        var requestHeaders = headers
        requestHeaders["Accept"] = "application/json"

        ConnectionTester.postJSON(url: url, headers: requestHeaders, body: body, completion: completion)
    }
}
