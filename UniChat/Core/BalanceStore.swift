import Foundation

/// Снимок баланса/квоты API-провайдера.
struct BalanceSnapshot {
    var remainingTokens: Double?
    var remainingUSD: Double?
    var pricePerMillion: Double?
    var modelID: String?
    var updatedAt: Date

    init(remainingTokens: Double? = nil,
         remainingUSD: Double? = nil,
         pricePerMillion: Double? = nil,
         modelID: String? = nil,
         updatedAt: Date = Date()) {
        self.remainingTokens = remainingTokens
        self.remainingUSD = remainingUSD
        self.pricePerMillion = pricePerMillion
        self.modelID = modelID
        self.updatedAt = updatedAt
    }
}

/// Хранит последний известный баланс и цены моделей (AnyModel).
/// Баланс AnyModel ведётся в токенах: 1M токенов базово стоит 5 центов.
final class BalanceStore {

    static let shared = BalanceStore()
    static let didChangeNotification = Notification.Name("UniChatBalanceDidChange")

    /// Базовая ставка AnyModel за 1M токенов.
    static let anyModelBasePricePerMillion: Double = 0.05

    private let defaults = UserDefaults.standard
    private let snapshotPrefix = "unichat.balance.snapshot."
    private let pricesPrefix = "unichat.balance.prices."

    private var snapshots: [UUID: BalanceSnapshot] = [:]
    private var prices: [UUID: [String: Double]] = [:]

    private init() {}

    // MARK: - Чтение

    func snapshot(for providerID: UUID) -> BalanceSnapshot? {
        if let cached = snapshots[providerID] { return cached }
        guard let stored = defaults.dictionary(forKey: snapshotPrefix + providerID.uuidString) else {
            return nil
        }

        let tokens = (stored["tokens"] as? NSNumber)?.doubleValue
        let usd = (stored["usd"] as? NSNumber)?.doubleValue
        let price = (stored["price"] as? NSNumber)?.doubleValue
        let date = (stored["date"] as? NSNumber)?.doubleValue
        let model = stored["model"] as? String

        let snapshot = BalanceSnapshot(
            remainingTokens: tokens,
            remainingUSD: usd,
            pricePerMillion: price,
            modelID: model,
            updatedAt: date.map { Date(timeIntervalSince1970: $0) } ?? Date.distantPast
        )
        snapshots[providerID] = snapshot
        return snapshot
    }

    func price(for providerID: UUID, model: String) -> Double? {
        let map = priceMap(for: providerID)
        if let exact = map[model] { return exact }

        let target = normalized(model)
        for (key, value) in map where normalized(key) == target {
            return value
        }
        for (key, value) in map where normalized(key).hasSuffix("/" + target) {
            return value
        }
        return nil
    }

    func allPrices(for providerID: UUID) -> [String: Double] {
        return priceMap(for: providerID)
    }

    // MARK: - Запись

    func setPrices(_ map: [String: Double], for providerID: UUID) {
        guard !map.isEmpty else { return }
        var current = priceMap(for: providerID)
        for (key, value) in map {
            current[key] = value
        }
        prices[providerID] = current

        let key = pricesPrefix + providerID.uuidString
        if let data = try? JSONSerialization.data(withJSONObject: current, options: []),
           let text = String(data: data, encoding: .utf8) {
            defaults.set(text, forKey: key)
        }
        NotificationCenter.default.post(name: BalanceStore.didChangeNotification, object: nil)
    }

    func capturePrice(price: Double, model: String, providerID: UUID) {
        apply(tokens: nil, usd: nil, price: price, modelID: model, providerID: providerID)
    }

    func remove(providerID: UUID) {
        snapshots.removeValue(forKey: providerID)
        prices.removeValue(forKey: providerID)
        defaults.removeObject(forKey: snapshotPrefix + providerID.uuidString)
        defaults.removeObject(forKey: pricesPrefix + providerID.uuidString)
    }

    /// Подписывается на заголовки ответа, чтобы поймать баланс AnyModel.
    func observe(providerID: UUID, session: StreamingSession) {
        session.onResponseHeaders = { [weak self] response in
            self?.capture(response: response, providerID: providerID)
        }
    }

    func capture(response: HTTPURLResponse, providerID: UUID) {
        var tokens: Double?
        var usd: Double?

        for (key, value) in response.allHeaderFields {
            let name = (key as? String ?? "").lowercased()
            let text = "\(value)"
            guard name.contains("balance")
                || name.contains("credit")
                || name.contains("quota")
                || name.contains("remaining") else { continue }

            guard let number = BalanceStore.number(from: text) else { continue }

            if name.contains("usd") || text.contains("$") {
                usd = number
            } else if name.contains("token") || name.contains("credit") || name.contains("quota") {
                tokens = number
            } else if number > 10_000 {
                tokens = number
            } else {
                usd = number
            }
        }

        guard tokens != nil || usd != nil else { return }
        DispatchQueue.main.async {
            self.apply(tokens: tokens, usd: usd, price: nil, modelID: nil, providerID: providerID)
        }
    }

    func ingest(json: Any, providerID: UUID) {
        var tokens: Double?
        var usd: Double?

        func walk(_ value: Any, key: String) {
            let lower = key.lowercased()
            if let number = value as? NSNumber {
                if lower.contains("token") || lower.contains("credit") || lower.contains("quota") {
                    tokens = number.doubleValue
                } else if lower.contains("usd") || lower.contains("money") || lower.contains("balance") {
                    usd = number.doubleValue
                }
                return
            }
            if let text = value as? String {
                guard lower.contains("balance") || lower.contains("credit")
                    || lower.contains("token") || lower.contains("remaining") else { return }
                if let number = BalanceStore.number(from: text) {
                    if lower.contains("token") || lower.contains("credit") {
                        tokens = number
                    } else if text.contains("$") || lower.contains("usd") {
                        usd = number
                    } else {
                        usd = number
                    }
                }
                return
            }
            if let dictionary = value as? [String: Any] {
                for (childKey, child) in dictionary {
                    walk(child, key: childKey)
                }
            }
            if let array = value as? [Any] {
                for child in array { walk(child, key: key) }
            }
        }

        walk(json, key: "")
        guard tokens != nil || usd != nil else { return }
        DispatchQueue.main.async {
            self.apply(tokens: tokens, usd: usd, price: nil, modelID: nil, providerID: providerID)
        }
    }

    private func apply(tokens: Double?,
                       usd: Double?,
                       price: Double?,
                       modelID: String?,
                       providerID: UUID) {
        var snapshot = snapshot(for: providerID) ?? BalanceSnapshot()
        if let tokens = tokens { snapshot.remainingTokens = tokens }
        if let usd = usd { snapshot.remainingUSD = usd }
        if let price = price { snapshot.pricePerMillion = price }
        if let modelID = modelID { snapshot.modelID = modelID }
        if snapshot.remainingTokens != nil && snapshot.remainingUSD == nil {
            snapshot.remainingUSD = snapshot.remainingTokens.map {
                $0 / 1_000_000.0 * BalanceStore.anyModelBasePricePerMillion
            }
        }
        snapshot.updatedAt = Date()
        snapshots[providerID] = snapshot

        var stored: [String: Any] = ["date": snapshot.updatedAt.timeIntervalSince1970]
        if let value = snapshot.remainingTokens { stored["tokens"] = value }
        if let value = snapshot.remainingUSD { stored["usd"] = value }
        if let value = snapshot.pricePerMillion { stored["price"] = value }
        if let value = snapshot.modelID { stored["model"] = value }
        defaults.set(stored, forKey: snapshotPrefix + providerID.uuidString)

        NotificationCenter.default.post(name: BalanceStore.didChangeNotification, object: nil)
    }

    // MARK: - Цены

    private func priceMap(for providerID: UUID) -> [String: Double] {
        if let cached = prices[providerID] { return cached }
        guard let text = defaults.string(forKey: pricesPrefix + providerID.uuidString),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        var result: [String: Double] = [:]
        for (key, value) in dictionary {
            if let number = value as? NSNumber { result[key] = number.doubleValue }
        }
        prices[providerID] = result
        return result
    }

    private func normalized(_ value: String) -> String {
        return value.lowercased()
            .replacingOccurrences(of: ":free", with: "")
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func number(from text: String) -> Double? {
        var value = text.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "≈", with: "")
            .replacingOccurrences(of: "USD", with: "")
            .replacingOccurrences(of: "usd", with: "")
            .replacingOccurrences(of: "tokens", with: "")
            .replacingOccurrences(of: "токенов", with: "")
            .replacingOccurrences(of: "%", with: "")
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'{}[]:;"))
        return Double(value)
    }
}

/// Цены и баланс AnyModel. Цена берётся из публичной таблицы /ru/pricing,
/// баланс — из заголовков ответов API и из доступных account-endpoint'ов.
enum AnyModelCatalog {

    static func isAnyModel(_ provider: ProviderConfig) -> Bool {
        return provider.baseURL.lowercased().contains("anymodel.org")
    }

    static func refresh(for provider: ProviderConfig) {
        guard isAnyModel(provider), provider.isReady else { return }
        refreshPrices(for: provider)
        refreshBalance(for: provider)
    }

    static func refreshPrices(for provider: ProviderConfig) {
        guard isAnyModel(provider), !provider.trimmedAPIKey.isEmpty else { return }

        fetchAPIPrices(provider: provider) { apiPrices in
            if !apiPrices.isEmpty {
                BalanceStore.shared.setPrices(apiPrices, for: provider.id)
                for (model, price) in apiPrices where !provider.model.isEmpty
                    && model == provider.model {
                    BalanceStore.shared.capturePrice(price: price,
                                                     model: model,
                                                     providerID: provider.id)
                    break
                }
            }
            fetchSitePrices { sitePrices in
                if !sitePrices.isEmpty {
                    BalanceStore.shared.setPrices(sitePrices, for: provider.id)
                }
            }
        }
    }

    private static func fetchAPIPrices(provider: ProviderConfig,
                                       completion: @escaping ([String: Double]) -> Void) {
        guard let url = URL(string: "https://anymodel.org/v1/models") else {
            completion([:])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer " + provider.trimmedAPIKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                completion([:])
                return
            }
            if let http = response as? HTTPURLResponse {
                BalanceStore.shared.capture(response: http, providerID: provider.id)
            }

            var result: [String: Double] = [:]
            let items: [[String: Any]]
            if let object = json as? [String: Any],
               let dataItems = object["data"] as? [[String: Any]] {
                items = dataItems
            } else if let dataItems = json as? [[String: Any]] {
                items = dataItems
            } else {
                items = []
            }

            for item in items {
                let identifier = item["id"] as? String ?? item["name"] as? String ?? ""
                guard !identifier.isEmpty else { continue }
                if let price = findPrice(item) {
                    result[identifier] = price
                }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private static func fetchSitePrices(completion: @escaping ([String: Double]) -> Void) {
        guard let url = URL(string: "https://anymodel.org/ru/pricing") else {
            completion([:])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 12_5_7 like Mac OS X) " +
                         "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil,
                  let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                completion([:])
                return
            }
            let pattern = "<option value=\"([a-zA-Z0-9]{2,8}/[a-zA-Z0-9][a-zA-Z0-9._-]*)\"[^>]*>[\\s\\S]*?\\$([0-9]+(?:\\.[0-9]+)?)</option>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                completion([:])
                return
            }
            let range = NSRange(location: 0, length: (html as NSString).length)
            let matches = regex.matches(in: html, options: [], range: range)
            var result: [String: Double] = [:]
            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let model = (html as NSString).substring(with: match.range(at: 1))
                let priceText = (html as NSString).substring(with: match.range(at: 2))
                if let price = Double(priceText) {
                    result[model] = price
                }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private static func refreshBalance(for provider: ProviderConfig) {
        let paths = ["/v1/me", "/v1/credits", "/v1/balance", "/v1/usage"]
        for path in paths {
            guard let url = URL(string: "https://anymodel.org" + path) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("Bearer " + provider.trimmedAPIKey, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            URLSession.shared.dataTask(with: request) { data, response, error in
                guard error == nil else { return }
                if let http = response as? HTTPURLResponse {
                    BalanceStore.shared.capture(response: http, providerID: provider.id)
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                    return
                }
                BalanceStore.shared.ingest(json: json, providerID: provider.id)
            }.resume()
        }
    }

    private static func findPrice(_ item: [String: Any]) -> Double? {
        func price(from value: Any, depth: Int) -> Double? {
            guard depth < 4 else { return nil }
            if let number = value as? NSNumber { return number.doubleValue }
            if let text = value as? String {
                return BalanceStore.number(from: text)
            }
            if let dictionary = value as? [String: Any] {
                let keys = ["per_million", "perMillion", "price_per_million", "pricePerMillion",
                            "input_price_per_million", "inputPricePerMillion", "input_price",
                            "inputPrice", "prompt", "input", "price", "x", "anyModelPrice"]
                for key in keys {
                    if let child = dictionary[key], let result = price(from: child, depth: depth + 1) {
                        return result
                    }
                }
                if let child = dictionary["pricing"], let result = price(from: child, depth: depth + 1) {
                    return result
                }
            }
            return nil
        }
        return price(from: item, depth: 0)
    }
}

/// Компактное форматирование денег, токенов и цены.
enum BalanceFormat {

    static func usd(_ value: Double) -> String {
        if value >= 100 { return String(format: "$%.0f", value) }
        if value >= 1 { return String(format: "$%.2f", value) }
        if value >= 0.01 { return String(format: "$%.3f", value) }
        return String(format: "$%.4f", value)
    }

    static func price(_ value: Double) -> String {
        if value == 0 { return "$0" }
        if value >= 1 { return String(format: "$%.2f/1M", value) }
        if value >= 0.01 { return String(format: "$%.3f/1M", value) }
        return String(format: "$%.4f/1M", value)
    }

    static func tokens(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}

