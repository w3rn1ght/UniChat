import Foundation

struct ChatRequest {
    var model: String
    var messages: [ChatMessage]
    var systemPrompt: String
    var temperature: Double?

    init(model: String,
         messages: [ChatMessage],
         systemPrompt: String = "",
         temperature: Double? = nil) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.temperature = temperature
    }

    var usableMessages: [ChatMessage] {
        return messages.filter { message in
            message.role != .system &&
            !message.isError &&
            !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var resolvedSystemPrompt: String {
        return systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Общий интерфейс провайдера.
protocol ChatProvider: AnyObject {
    var config: ProviderConfig { get }

    /// Запускает стриминг. Возвращает объект для отмены (или nil, если запрос не начался).
    func streamChat(_ chat: ChatRequest,
                    onDelta: @escaping (String) -> Void,
                    onFinish: @escaping (Error?) -> Void) -> CancellableTask?

    /// Проверка ключа/адреса.
    func testConnection(completion: @escaping (Result<String, Error>) -> Void)
}

/// Вспомогательные сетевые вызовы для проверки подключения.
enum ConnectionTester {

    static func get(url: URL,
                    headers: [String: String],
                    completion: @escaping (Result<String, Error>) -> Void) {

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        for (key, value) in headers where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<String, Error>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }

            if let error = error {
                finish(.failure(ChatError.network(error)))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            if status >= 200 && status < 300 {
                finish(.success("Подключение успешно (HTTP \(status))."))
            } else {
                finish(.failure(ChatError.http(status: status, body: body)))
            }
        }.resume()
    }

    static func postJSON(url: URL,
                         headers: [String: String],
                         body: [String: Any],
                         completion: @escaping (Result<String, Error>) -> Void) {

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            completion(.failure(ChatError(message: "Не удалось собрать тестовый запрос.")))
            return
        }
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finish: (Result<String, Error>) -> Void = { result in
                DispatchQueue.main.async { completion(result) }
            }

            if let error = error {
                finish(.failure(ChatError.network(error)))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            if status >= 200 && status < 300 {
                finish(.success("Модель ответила (HTTP \(status))."))
            } else {
                finish(.failure(ChatError.http(status: status, body: responseBody)))
            }
        }.resume()
    }
}
