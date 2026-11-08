import Foundation

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

/// Одно сообщение в диалоге.
struct ChatMessage: Codable, Equatable {
    var id: UUID
    var role: MessageRole
    var text: String
    var createdAt: Date
    var isError: Bool
    var modelName: String?

    init(id: UUID = UUID(),
         role: MessageRole,
         text: String,
         createdAt: Date = Date(),
         isError: Bool = false,
         modelName: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isError = isError
        self.modelName = modelName
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text, createdAt, isError, modelName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decodeIfPresent(MessageRole.self, forKey: .role) ?? .assistant
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
    }
}

/// Диалог (чат).
struct Conversation: Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var providerID: UUID?
    var model: String?
    var systemPrompt: String?
    var messages: [ChatMessage]

    init(id: UUID = UUID(),
         title: String = "Новый чат",
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         providerID: UUID? = nil,
         model: String? = nil,
         systemPrompt: String? = nil,
         messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.providerID = providerID
        self.model = model
        self.systemPrompt = systemPrompt
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, providerID, model, systemPrompt, messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Новый чат"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        providerID = try container.decodeIfPresent(UUID.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }

    var isEmpty: Bool {
        return messages.isEmpty
    }

    var previewText: String {
        guard let last = messages.last(where: { !$0.text.isEmpty }) else { return "Пустой диалог" }
        let flattened = last.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flattened.count <= 90 { return flattened }
        return String(flattened.prefix(90)) + "…"
    }

    func messagesForRequest() -> [ChatMessage] {
        return messages.filter { message in
            !message.isError &&
            !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
