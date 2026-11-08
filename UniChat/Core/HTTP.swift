import Foundation

/// Ошибка чата с человекочитаемым русским описанием.
struct ChatError: LocalizedError {
    let message: String

    var errorDescription: String? { return message }

    static func http(status: Int, body: String) -> ChatError {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = trimmed.count > 500 ? String(trimmed.prefix(500)) + "…" : trimmed

        let hint: String
        switch status {
        case 400:
            hint = "Провайдер отклонил запрос (400). Проверьте название модели и параметры."
        case 401:
            hint = "Неверный или отсутствующий API-ключ (401)."
        case 402:
            hint = "Закончились средства на счёте провайдера (402)."
        case 403:
            hint = "Доступ запрещён (403). Проверьте ключ и доступность модели."
        case 404:
            hint = "Не найдено (404). Проверьте Base URL и название модели."
        case 429:
            hint = "Слишком много запросов или исчерпан лимит (429). Попробуйте позже."
        case 500...599:
            hint = "Ошибка на стороне провайдера (HTTP \(status))."
        default:
            hint = "HTTP \(status)."
        }

        return ChatError(message: snippet.isEmpty ? hint : hint + "\n\n" + snippet)
    }

    static func network(_ error: Error) -> ChatError {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return ChatError(message: "Ошибка: \(nsError.localizedDescription)")
        }

        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return ChatError(message: "Нет подключения к интернету.")
        case NSURLErrorTimedOut:
            return ChatError(message: "Превышено время ожидания. Проверьте сеть или релей.")
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return ChatError(message: "Не удалось найти сервер. Домен может быть заблокирован — укажите релей (см. «Настройки»).")
        case NSURLErrorCannotConnectToHost:
            return ChatError(message: "Не удалось подключиться к серверу. Возможно, он заблокирован или недоступен. Используйте релей.")
        case NSURLErrorNetworkConnectionLost:
            return ChatError(message: "Соединение потеряно. Попробуйте ещё раз.")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return ChatError(message: "Ошибка TLS/сертификата. Проверьте адрес релея.")
        case NSURLErrorCancelled:
            return ChatError(message: "Запрос отменён.")
        default:
            return ChatError(message: "Сетевая ошибка: \(nsError.localizedDescription)")
        }
    }
}

/// Запрос, который можно отменить.
protocol CancellableTask: class {
    func cancel()
}

/// Разбирает SSE-поток (text/event-stream) и обычный JSON-ответ.
final class StreamingSession: NSObject, URLSessionDataDelegate, CancellableTask {

    private var session: URLSession?
    private var task: URLSessionDataTask?

    private var onEvent: ((String) -> Void)?
    private var onFinish: ((Error?) -> Void)?

    private var buffer = Data()
    private var rawBody = Data()
    private var eventLines: [String] = []

    private var isSSE = false
    private var statusCode = 0
    private var finished = false

    func start(request: URLRequest,
               onEvent: @escaping (String) -> Void,
               onFinish: @escaping (Error?) -> Void) {

        self.onEvent = onEvent
        self.onFinish = onFinish

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session

        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        finish(ChatError(message: "Запрос отменён."))
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true

        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil

        let callback = onFinish
        onFinish = nil
        onEvent = nil

        callback?(error)
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {

        if let http = response as? HTTPURLResponse {
            statusCode = http.statusCode
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            isSSE = contentType.contains("text/event-stream")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }

        if statusCode >= 400 {
            rawBody.append(data)
            return
        }

        if isSSE {
            buffer.append(data)
            processBuffer()
        } else {
            rawBody.append(data)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {

        guard !finished else { return }

        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                finish(nil)
            } else {
                finish(ChatError.network(error))
            }
            return
        }

        if statusCode >= 400 {
            let body = String(data: rawBody, encoding: .utf8) ?? ""
            finish(ChatError.http(status: statusCode, body: body))
            return
        }

        if isSSE {
            flushRemainingBuffer()
            dispatchEvent()
            finish(nil)
        } else {
            if let text = String(data: rawBody, encoding: .utf8), !text.isEmpty {
                onEvent?(text)
            }
            finish(nil)
        }
    }

    // MARK: - SSE parsing

    private func processBuffer() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[buffer.startIndex..<newline]
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            let line = String(decoding: lineData, as: UTF8.self)
            let end = buffer.index(after: newline)
            buffer.removeSubrange(buffer.startIndex..<end)
            handle(line: line)
        }
    }

    private func flushRemainingBuffer() {
        guard !buffer.isEmpty else { return }
        let text = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        for line in text.components(separatedBy: "\n") {
            handle(line: line.replacingOccurrences(of: "\r", with: ""))
        }
    }

    private func handle(line: String) {
        if line.isEmpty {
            dispatchEvent()
            return
        }
        if line.hasPrefix(":") {
            return
        }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            eventLines.append(value)
            return
        }
        // event:, id:, retry: — игнорируем
    }

    private func dispatchEvent() {
        guard !eventLines.isEmpty else { return }
        let payload = eventLines.joined(separator: "\n")
        eventLines.removeAll()
        guard !payload.isEmpty else { return }
        onEvent?(payload)
    }
}
