import Foundation

enum DeepSeekWeb {
    static let baseURL = "https://chat.deepseek.com"
    static let completionPath = "/api/v0/chat/completion"
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    static func headers(token: String) -> [String: String] {
        return [
            "Accept": "*/*",
            "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "Origin": baseURL,
            "Referer": baseURL + "/",
            "User-Agent": userAgent,
            "x-app-version": "2.0.0",
            "x-client-locale": "en_US",
            "x-client-platform": "web",
            "x-client-timezone-offset": String(TimeZone.current.secondsFromGMT()),
            "x-client-version": "2.0.0"
        ]
    }
}

/// DeepSeek через обычный веб-аккаунт chat.deepseek.com.
///
/// Логин выполняется в WKWebView, из localStorage забирается userToken.
/// Дальше запросы идут нативный URLSession к тем же приватным endpoint'ам,
/// что использует сайт, включая proof-of-work.
final class DeepSeekAccountProvider: ChatProvider {

    let config: ProviderConfig

    init(config: ProviderConfig) {
        self.config = config
    }

    private var token: String {
        return config.trimmedAccountToken
    }

    // MARK: - Chat

    func streamChat(_ chat: ChatRequest,
                    onDelta: @escaping (String) -> Void,
                    onFinish: @escaping (Error?) -> Void) -> CancellableTask? {

        guard !token.isEmpty else {
            onFinish(ChatError(message: "Войдите в аккаунт DeepSeek в настройках провайдера."))
            return nil
        }

        let model = (chat.model.isEmpty ? config.model : chat.model)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = AccountPrompt.build(chat)
        let lower = model.lowercased()
        let thinking = lower.contains("reason") || lower.contains("r1") || lower.contains("think")
        let search = lower.contains("search")

        let task = DeepSeekStreamTask()
        task.onDelta = onDelta
        task.onFinish = onFinish

        let currentToken = token
        createSession(token: currentToken) { [weak self] result in
            guard let self = self else { return }
            if task.isCancelled { return }

            switch result {
            case .failure(let error):
                task.finish(error)

            case .success(let sessionID):
                task.sessionID = sessionID
                self.createChallenge(token: currentToken) { challengeResult in
                    if task.isCancelled { return }

                    switch challengeResult {
                    case .failure(let error):
                        task.finish(error)

                    case .success(let challenge):
                        DeepSeekPoWSolver.shared.solve(challenge: challenge) { solveResult in
                            if task.isCancelled { return }

                            switch solveResult {
                            case .failure(let error):
                                task.finish(error)

                            case .success(let answer):
                                guard let powHeader = self.makePoWHeader(challenge: challenge, answer: answer) else {
                                    task.finish(ChatError(message: "Не удалось собрать PoW-заголовок DeepSeek."))
                                    return
                                }
                                self.startCompletion(token: currentToken,
                                                     sessionID: sessionID,
                                                     prompt: prompt,
                                                     thinking: thinking,
                                                     search: search,
                                                     powHeader: powHeader,
                                                     task: task)
                            }
                        }
                    }
                }
            }
        }

        return task
    }

    // MARK: - Шаги запроса

    private func createSession(token: String,
                               completion: @escaping (Result<String, Error>) -> Void) {
        request(path: "/api/v0/chat_session/create",
                method: "POST",
                body: [:],
                token: token) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let object):
                let data = object["data"] as? [String: Any]
                let biz = data?["biz_data"] as? [String: Any]
                let session = biz?["chat_session"] as? [String: Any]
                if let id = self.stringValue(session?["id"]) ?? self.stringValue(biz?["id"]) {
                    completion(.success(id))
                } else {
                    completion(.failure(ChatError(message: "DeepSeek не создал чат-сессию.")))
                }
            }
        }
    }

    private func createChallenge(token: String,
                                 completion: @escaping (Result<[String: Any], Error>) -> Void) {
        request(path: "/api/v0/chat/create_pow_challenge",
                method: "POST",
                body: ["target_path": DeepSeekWeb.completionPath],
                token: token) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let object):
                let data = object["data"] as? [String: Any]
                let biz = data?["biz_data"] as? [String: Any]
                if let challenge = biz?["challenge"] as? [String: Any] {
                    completion(.success(challenge))
                } else {
                    completion(.failure(ChatError(message: "DeepSeek не выдал PoW-задачу. Возможно, нужен повторный вход.")))
                }
            }
        }
    }

    private func makePoWHeader(challenge: [String: Any], answer: Int) -> String? {
        let payload: [String: Any] = [
            "algorithm": challenge["algorithm"] ?? "DeepSeekHashV1",
            "challenge": challenge["challenge"] ?? "",
            "salt": challenge["salt"] ?? "",
            "answer": answer,
            "signature": challenge["signature"] ?? "",
            "target_path": challenge["target_path"] ?? DeepSeekWeb.completionPath
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return nil
        }
        return data.base64EncodedString()
    }

    private func startCompletion(token: String,
                                 sessionID: String,
                                 prompt: String,
                                 thinking: Bool,
                                 search: Bool,
                                 powHeader: String,
                                 task: DeepSeekStreamTask) {

        guard let url = URL(string: DeepSeekWeb.baseURL + DeepSeekWeb.completionPath) else {
            task.finish(ChatError(message: "Некорректный адрес DeepSeek."))
            return
        }

        var body: [String: Any] = [
            "chat_session_id": sessionID,
            "parent_message_id": NSNull(),
            "prompt": prompt,
            "ref_file_ids": [],
            "thinking_enabled": thinking,
            "search_enabled": search,
            "action": NSNull(),
            "preempt": false
        ]
        if !search {
            body["search_enabled"] = false
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            task.finish(ChatError(message: "Не удалось собрать запрос DeepSeek."))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 300
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(powHeader, forHTTPHeaderField: "X-DS-PoW-Response")
        for (key, value) in DeepSeekWeb.headers(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let state = DeepSeekStreamState()
        var previousThink = ""
        var previousText = ""
        var didStartThinking = false

        let stream = StreamingSession()
        task.streamSession = stream

        stream.start(request: request, dispatchDataPerLine: true, onEvent: { payload in
            if task.isCancelled { return }

            state.consume(payload)

            if let error = state.error {
                task.finish(error)
                stream.cancel()
                return
            }

            let think = state.thinkText
            if thinking && think != previousThink {
                if think.hasPrefix(previousThink) {
                    let delta = String(think.dropFirst(previousThink.count))
                    if !delta.isEmpty {
                        if !didStartThinking {
                            didStartThinking = true
                            task.emit("\n\n💭 **Размышления**\n")
                        }
                        task.emit(delta)
                    }
                } else if !think.isEmpty {
                    didStartThinking = true
                    task.emit("\u{0}" + "\n\n💭 **Размышления**\n" + think)
                }
                previousThink = think
            }

            let text = state.responseText
            if text != previousText {
                if text.hasPrefix(previousText) {
                    let delta = String(text.dropFirst(previousText.count))
                    if !delta.isEmpty {
                        if didStartThinking {
                            task.emit("\n\n---\n\n")
                            didStartThinking = false
                        }
                        task.emit(delta)
                    }
                } else if !text.isEmpty {
                    task.emit("\u{0}" + text)
                }
                previousText = text
            }
        }, onFinish: { [weak self] error in
            if let sessionID = task.sessionID {
                self?.deleteSession(sessionID, token: token)
            }

            if let error = error {
                task.finish(error)
                return
            }

            if let streamError = state.error {
                task.finish(streamError)
                return
            }

            let incomplete = (state.status ?? "").uppercased() == "INCOMPLETE"
            let answer = state.responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if incomplete && answer.isEmpty {
                task.finish(ChatError(message: "DeepSeek остановился до ответа. Попробуйте ещё раз."))
            } else if answer.isEmpty {
                task.finish(ChatError(message: "DeepSeek вернул пустой ответ."))
            } else {
                task.finish(nil)
            }
        })
    }

    private func deleteSession(_ sessionID: String, token: String) {
        request(path: "/api/v0/chat_session/delete",
                method: "POST",
                body: ["chat_session_id": sessionID],
                token: token,
                silently: true) { _ in }
    }

    // MARK: - Сеть

    private func request(path: String,
                         method: String,
                         body: [String: Any]?,
                         token: String,
                         extraHeaders: [String: String] = [:],
                         silently: Bool = false,
                         completion: @escaping (Result<[String: Any], Error>) -> Void) {

        guard let url = URL(string: DeepSeekWeb.baseURL + path) else {
            completion(.failure(ChatError(message: "Некорректный адрес DeepSeek.")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        for (key, value) in DeepSeekWeb.headers(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if method != "GET", let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        }

        let finish: (Result<[String: Any], Error>) -> Void = { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if silently {
                    finish(.failure(ChatError.network(error)))
                } else {
                    finish(.failure(ChatError.network(error)))
                }
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            if status == 401 || status == 403 {
                if silently {
                    finish(.failure(ChatError(message: "DeepSeek: нет доступа.")))
                } else {
                    finish(.failure(self.authenticationError()))
                }
                return
            }
            if status == 429 {
                finish(.failure(ChatError(message: "DeepSeek: слишком много запросов. Подождите немного.")))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []),
                  let object = json as? [String: Any] else {
                finish(.failure(ChatError.http(status: status, body: text)))
                return
            }

            if let code = object["code"] as? Int, code != 0 {
                let message = object["msg"] as? String ?? "код \(code)"
                if code == 40003 || message.lowercased().contains("token") || message.lowercased().contains("auth") {
                    finish(.failure(self.authenticationError()))
                } else {
                    finish(.failure(ChatError(message: "DeepSeek: " + message)))
                }
                return
            }

            if let dataObject = object["data"] as? [String: Any],
               let bizCode = dataObject["biz_code"] as? Int,
               bizCode != 0 {
                let message = dataObject["biz_msg"] as? String ?? "biz_code \(bizCode)"
                finish(.failure(ChatError(message: "DeepSeek: " + message)))
                return
            }

            finish(.success(object))
        }.resume()
    }

    private func stringValue(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func authenticationError() -> ChatError {
        DispatchQueue.main.async {
            guard var current = AppSettings.shared.provider(id: self.config.id) else { return }
            current.accountToken = ""
            current.accountConnected = false
            current.accountEmail = ""
            AppSettings.shared.upsert(current)
        }
        return ChatError(message: "Сессия DeepSeek истекла или отозвана. Войдите в аккаунт снова.")
    }

    private func updateAccount(email: String, connected: Bool) {
        DispatchQueue.main.async {
            guard var current = AppSettings.shared.provider(id: self.config.id) else { return }
            current.accountConnected = connected
            if connected {
                if !email.isEmpty { current.accountEmail = email }
            } else {
                current.accountEmail = ""
            }
            AppSettings.shared.upsert(current)
        }
    }

    // MARK: - Проверка

    func testConnection(completion: @escaping (Result<String, Error>) -> Void) {
        guard !token.isEmpty else {
            completion(.failure(ChatError(message: "Войдите в аккаунт DeepSeek.")))
            return
        }

        request(path: "/api/v0/users/current",
                method: "GET",
                body: nil,
                token: token) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let object):
                var email = ""
                if let data = object["data"] as? [String: Any] {
                    let biz = data["biz_data"] as? [String: Any]
                        ?? data["user"] as? [String: Any]
                        ?? data
                    if let value = biz["email"] as? String {
                        email = value
                    } else if let value = biz["mobile_number"] as? String {
                        email = value
                    }
                }
                self.updateAccount(email: email, connected: true)
                if email.isEmpty {
                    completion(.success("DeepSeek: аккаунт подключён."))
                } else {
                    completion(.success("DeepSeek: " + email))
                }
            }
        }
    }
}

// MARK: - Состояние SSE

private final class DeepSeekStreamState {

    private var fragments: [[String: Any]] = []
    private var legacy = ""
    private var path: String?
    private(set) var finishReason: String?
    private(set) var status: String?
    private(set) var error: ChatError?

    var thinkText: String {
        var result = ""
        for fragment in fragments {
            let type = fragment["type"] as? String ?? ""
            if type == "THINK" || type == "REASONING",
               let content = fragment["content"] as? String {
                result += content
            }
        }
        return result
    }

    var responseText: String {
        var result = ""
        for fragment in fragments {
            if (fragment["type"] as? String) == "RESPONSE",
               let content = fragment["content"] as? String {
                result += content
            }
        }
        return result + legacy
    }

    func consume(_ payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[DONE]" else { return }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return
        }
        feed(dictionary)
    }

    private func feed(_ dictionary: [String: Any]) {
        if let type = dictionary["type"] as? String, type == "error" || type == "hint" {
            let content = dictionary["content"] as? String
                ?? dictionary["finish_reason"] as? String
                ?? "ошибка"
            if content.lowercased().contains("rate") || content.lowercased().contains("many") {
                error = ChatError(message: "DeepSeek: слишком много запросов. Подождите немного.")
            } else if type == "error" {
                error = ChatError(message: "DeepSeek: " + content)
            }
        }

        if let value = dictionary["finish_reason"] as? String {
            finishReason = value
        }
        if let value = dictionary["p"] as? String {
            path = value
        }

        if let value = dictionary["v"] as? [String: Any] {
            if let response = value["response"] as? [String: Any] {
                if let list = response["fragments"] as? [[String: Any]] {
                    fragments = list
                }
                if let content = response["content"] as? String {
                    legacy = content
                }
                if let value = response["status"] as? String {
                    status = value
                }
                return
            }
        }

        guard let currentPath = path else { return }

        if currentPath == "response/fragments" {
            if let fragment = dictionary["v"] as? [String: Any] {
                fragments.append(fragment)
            } else if let list = dictionary["v"] as? [[String: Any]] {
                fragments.append(contentsOf: list)
            }
        } else if currentPath == "response" {
            if let operations = dictionary["v"] as? [[String: Any]] {
                for operation in operations {
                    if (operation["p"] as? String) == "fragments",
                       (operation["o"] as? String) == "APPEND" {
                        if let fragment = operation["v"] as? [String: Any] {
                            fragments.append(fragment)
                        } else if let list = operation["v"] as? [[String: Any]] {
                            fragments.append(contentsOf: list)
                        }
                    }
                }
            }
        } else if currentPath == "response/fragments/-1/content" {
            if let value = dictionary["v"] as? String, !fragments.isEmpty {
                var last = fragments[fragments.count - 1]
                let content = last["content"] as? String ?? ""
                last["content"] = content + value
                fragments[fragments.count - 1] = last
            }
        } else if currentPath == "response/content" {
            if let value = dictionary["v"] as? String {
                legacy += value
            }
        } else if currentPath == "response/status" {
            if let value = dictionary["v"] as? String {
                status = value
            }
        } else if currentPath == "response/finish_reason" {
            if let value = dictionary["v"] as? String {
                finishReason = value
            }
        }
    }
}

// MARK: - Отменяемая задача

private final class DeepSeekStreamTask: CancellableTask {

    private(set) var isCancelled = false
    private var isFinished = false
    var sessionID: String?
    var streamSession: StreamingSession?
    var onDelta: ((String) -> Void)?
    var onFinish: ((Error?) -> Void)?

    func cancel() {
        guard !isFinished else { return }
        isCancelled = true
        streamSession?.cancel()
        finish(ChatError(message: "Запрос отменён."))
    }

    func emit(_ text: String) {
        guard !text.isEmpty, !isCancelled, !isFinished else { return }
        DispatchQueue.main.async {
            guard !self.isCancelled, !self.isFinished else { return }
            self.onDelta?(text)
        }
    }

    func finish(_ error: Error?) {
        guard !isFinished else { return }
        isFinished = true
        streamSession = nil
        DispatchQueue.main.async {
            let callback = self.onFinish
            self.onFinish = nil
            self.onDelta = nil
            callback?(error)
        }
    }
}
