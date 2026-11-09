import Foundation

/// Автопоиск моделей у OpenAI-совместимых шлюзов и Gemini API.
enum ModelCatalog {

    static func supportsDiscovery(_ kind: ProviderKind) -> Bool {
        switch kind {
        case .openAICompatible, .gemini:
            return true
        case .deepSeekAccount, .geminiAccount:
            return false
        }
    }

    /// Загружает список идентификаторов моделей и возвращает его в главном потоке.
    static func fetch(for provider: ProviderConfig,
                      completion: @escaping (Result<[String], Error>) -> Void) {

        switch provider.kind {
        case .deepSeekAccount:
            let models = provider.modelPresets.isEmpty
                ? ["deepseek-chat", "deepseek-reasoner"]
                : provider.modelPresets
            DispatchQueue.main.async { completion(.success(models)) }
            return
        case .geminiAccount:
            let models = provider.modelPresets.isEmpty
                ? ["gemini-flash", "gemini-pro", "gemini-flash-lite", "auto"]
                : provider.modelPresets
            DispatchQueue.main.async { completion(.success(models)) }
            return
        case .openAICompatible:
            fetchOpenAICompatible(provider: provider, completion: completion)
        case .gemini:
            fetchGemini(provider: provider, completion: completion)
        }
    }

    // MARK: - OpenAI-совместимые

    private static func fetchOpenAICompatible(provider: ProviderConfig,
                                              completion: @escaping (Result<[String], Error>) -> Void) {
        let base = provider.normalizedBaseURL
        guard !base.isEmpty, let url = URL(string: base + "/models") else {
            completion(.failure(ChatError(message: "Некорректный Base URL для поиска моделей.")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !provider.trimmedAPIKey.isEmpty {
            request.setValue("Bearer " + provider.trimmedAPIKey, forHTTPHeaderField: "Authorization")
        }
        if let referer = provider.extraHeaders["HTTP-Referer"] {
            request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        }
        if let title = provider.extraHeaders["X-Title"] {
            request.setValue(title, forHTTPHeaderField: "X-Title")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<[String], Error>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }

            if let error = error {
                finish(.failure(ChatError.network(error)))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            guard status >= 200 && status < 300 else {
                finish(.failure(ChatError.http(status: status, body: body)))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                finish(.failure(ChatError(message: "Провайдер вернул не JSON при поиске моделей.")))
                return
            }

            let models = parseOpenAIModels(json)
            if models.isEmpty {
                finish(.failure(ChatError(message: "Список моделей пуст. Проверьте Base URL и ключ.")))
            } else {
                finish(.success(models))
            }
        }.resume()
    }

    private static func parseOpenAIModels(_ json: Any) -> [String] {
        var rawItems: [Any] = []

        if let array = json as? [Any] {
            rawItems = array
        } else if let object = json as? [String: Any] {
            if let array = object["data"] as? [Any] {
                rawItems = array
            } else if let array = object["models"] as? [Any] {
                rawItems = array
            } else if let array = object["result"] as? [Any] {
                rawItems = array
            }
        }

        var seen = Set<String>()
        var result: [String] = []

        for item in rawItems {
            var identifier: String?
            if let text = item as? String {
                identifier = text
            } else if let object = item as? [String: Any] {
                identifier = object["id"] as? String
                    ?? object["name"] as? String
                    ?? object["model"] as? String
                    ?? object["slug"] as? String
            }
            guard let value = identifier else { continue }
            let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty, !seen.contains(model) else { continue }
            seen.insert(model)
            result.append(model)
        }

        return result.sorted { a, b in
            let aFree = a.lowercased().hasSuffix(":free")
            let bFree = b.lowercased().hasSuffix(":free")
            if aFree != bFree { return aFree }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    // MARK: - Gemini API

    private static func fetchGemini(provider: ProviderConfig,
                                    completion: @escaping (Result<[String], Error>) -> Void) {
        let base = provider.normalizedBaseURL
        guard !base.isEmpty else {
            completion(.failure(ChatError(message: "Не задан Base URL Gemini.")))
            return
        }
        guard !provider.trimmedAPIKey.isEmpty else {
            completion(.failure(ChatError(message: "Для поиска моделей нужен API-ключ Gemini.")))
            return
        }

        var root = base
        if !root.hasSuffix("/v1beta") && !root.hasSuffix("/v1") {
            root += "/v1beta"
        }
        guard let url = URL(string: root + "/models") else {
            completion(.failure(ChatError(message: "Некорректный Base URL Gemini.")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(provider.trimmedAPIKey, forHTTPHeaderField: "x-goog-api-key")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<[String], Error>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }

            if let error = error {
                finish(.failure(ChatError.network(error)))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            guard status >= 200 && status < 300 else {
                finish(.failure(ChatError.http(status: status, body: body)))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []),
                  let object = json as? [String: Any],
                  let rawModels = object["models"] as? [[String: Any]] else {
                finish(.failure(ChatError(message: "Gemini не вернул список моделей.")))
                return
            }

            var seen = Set<String>()
            var models: [String] = []

            for item in rawModels {
                guard let name = item["name"] as? String else { continue }
                let methods = item["supportedGenerationMethods"] as? [String] ?? []
                if !methods.isEmpty && !methods.contains("generateContent") { continue }

                var model = name
                if model.hasPrefix("models/") {
                    model = String(model.dropFirst("models/".count))
                }
                guard !model.isEmpty, !seen.contains(model) else { continue }
                seen.insert(model)
                models.append(model)
            }

            if models.isEmpty {
                finish(.failure(ChatError(message: "Нет доступных моделей Gemini для этого ключа.")))
            } else {
                finish(.success(models.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }))
            }
        }.resume()
    }

    // MARK: - Массовое обновление

    /// Обновляет списки моделей у всех готовых провайдеров. Модели сохраняются
    /// в настройках, поэтому в следующий раз список доступен сразу.
    static func refreshAll(_ providers: [ProviderConfig], completion: (() -> Void)? = nil) {
        let targets = providers.filter { provider in
            return supportsDiscovery(provider.kind)
                && !provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && provider.isReady
        }
        guard !targets.isEmpty else {
            DispatchQueue.main.async { completion?() }
            return
        }

        let group = DispatchGroup()

        for provider in targets {
            group.enter()
            fetch(for: provider) { result in
                defer { group.leave() }
                guard case .success(let models) = result, !models.isEmpty else { return }

                let latest = AppSettings.shared.provider(id: provider.id) ?? provider
                var merged = models
                if !latest.model.isEmpty && !merged.contains(latest.model) {
                    merged.insert(latest.model, at: 0)
                }

                var updated = latest
                updated.modelPresets = merged
                if updated.model.isEmpty {
                    updated.model = merged[0]
                }
                AppSettings.shared.upsert(updated)
            }
        }

        group.notify(queue: .main) {
            completion?()
        }
    }

    /// Сливает свежий список с уже сохранёнными моделями, не теряя выбранную.
    static func merged(_ models: [String], with provider: ProviderConfig) -> [String] {
        var result = models
        if !provider.model.isEmpty && !result.contains(provider.model) {
            result.insert(provider.model, at: 0)
        }
        return result
    }
}
