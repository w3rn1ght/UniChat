import Foundation

/// Google Gemini через официальный API (AI Studio key) или через собственный релей.
final class GeminiProvider: ChatProvider {

    let config: ProviderConfig

    init(config: ProviderConfig) {
        self.config = config
    }

    private var apiRoot: String {
        let base = config.normalizedBaseURL
        if base.hasSuffix("/v1beta") || base.hasSuffix("/v1") {
            return base
        }
        return base + "/v1beta"
    }

    private func cleanModelName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("models/") {
            name = String(name.dropFirst("models/".count))
        }
        return name
    }

    private var headers: [String: String] {
        var result: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "x-goog-api-key": config.trimmedAPIKey
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

        guard !config.normalizedBaseURL.isEmpty else {
            onFinish(ChatError(message: "Не задан Base URL для Gemini."))
            return nil
        }
        guard config.hasAPIKey else {
            onFinish(ChatError(message: "Не задан API-ключ Gemini.\nПолучите бесплатный ключ в Google AI Studio."))
            return nil
        }

        let model = cleanModelName(chat.model.isEmpty ? config.model : chat.model)
        guard !model.isEmpty else {
            onFinish(ChatError(message: "Не задана модель Gemini."))
            return nil
        }

        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/")
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              var components = URLComponents(string: apiRoot + "/models/" + encodedModel + ":streamGenerateContent") else {
            onFinish(ChatError(message: "Некорректный Base URL Gemini."))
            return nil
        }
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components.url else {
            onFinish(ChatError(message: "Не удалось собрать URL Gemini."))
            return nil
        }

        var contents: [[String: Any]] = []
        for message in chat.usableMessages {
            let role = message.role == .assistant ? "model" : "user"
            if var last = contents.last,
               (last["role"] as? String) == role,
               var parts = last["parts"] as? [[String: Any]] {
                parts.append(["text": message.text])
                last["parts"] = parts
                contents[contents.count - 1] = last
            } else {
                contents.append([
                    "role": role,
                    "parts": [["text": message.text]]
                ])
            }
        }

        guard !contents.isEmpty else {
            onFinish(ChatError(message: "Пустой запрос."))
            return nil
        }

        var body: [String: Any] = ["contents": contents]
        if !chat.resolvedSystemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": chat.resolvedSystemPrompt]]]
        }
        if let temperature = chat.temperature {
            body["generationConfig"] = ["temperature": temperature]
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
            guard !trimmed.isEmpty else { return }

            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                return
            }

            var objects: [[String: Any]] = []
            if let array = json as? [[String: Any]] {
                objects = array
            } else if let object = json as? [String: Any] {
                objects = [object]
            }

            for object in objects {
                if let error = object["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "неизвестная ошибка"
                    streamError = ChatError(message: "Gemini: " + message)
                    continue
                }

                if let feedback = object["promptFeedback"] as? [String: Any] {
                    if let blockReason = feedback["blockReason"] as? String {
                        streamError = ChatError(message: "Gemini заблокировал запрос: \(blockReason).")
                        continue
                    }
                    if let ratings = feedback["safetyRatings"] as? [[String: Any]] {
                        for rating in ratings {
                            if let blocked = rating["blocked"] as? Bool, blocked {
                                let category = rating["category"] as? String ?? "safety"
                                streamError = ChatError(message: "Gemini заблокировал запрос (\(category)).")
                            }
                        }
                    }
                }

                guard let candidates = object["candidates"] as? [[String: Any]] else { continue }

                for candidate in candidates {
                    if let content = candidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]] {
                        for part in parts {
                            if let thought = part["thought"] as? Bool, thought { continue }
                            if let text = part["text"] as? String, !text.isEmpty {
                                emit(text)
                            }
                        }
                    }

                    if let finishReason = candidate["finishReason"] as? String {
                        switch finishReason {
                        case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII":
                            streamError = ChatError(message: "Ответ остановлен фильтром Gemini (\(finishReason)).")
                        default:
                            break
                        }
                    }
                }
            }
        }, onFinish: { error in
            finishOnce(error)
        })

        return session
    }

    // MARK: - Проверка

    func testConnection(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: apiRoot + "/models") else {
            completion(.failure(ChatError(message: "Некорректный Base URL Gemini.")))
            return
        }
        guard config.hasAPIKey else {
            completion(.failure(ChatError(message: "Не задан API-ключ Gemini.")))
            return
        }

        ConnectionTester.get(url: url,
                             headers: ["x-goog-api-key": config.trimmedAPIKey],
                             completion: completion)
    }
}
