import Foundation

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

enum ChatAttachmentKind: String, Codable {
    case image
    case file
}

/// Вложение сообщения. Данные хранятся в самом чате (base64 внутри JSON),
/// поэтому вложение остаётся доступным после перезапуска приложения.
struct ChatAttachment: Codable, Equatable {
    var id: UUID
    var name: String
    var mimeType: String
    var kind: ChatAttachmentKind
    var data: Data

    init(id: UUID = UUID(),
         name: String,
         mimeType: String,
         kind: ChatAttachmentKind,
         data: Data) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.kind = kind
        self.data = data
    }

    var isImage: Bool {
        return kind == .image && mimeType.lowercased().hasPrefix("image/")
    }

    var sizeText: String {
        return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    /// Текст файла, если это текстовый формат (txt, md, json, csv, код и т.п.).
    func textContent() -> String? {
        let lower = mimeType.lowercased()
        let isText = lower.hasPrefix("text/")
            || lower == "application/json"
            || lower == "application/xml"
            || lower == "application/javascript"
            || lower == "application/x-javascript"
            || lower == "application/x-yaml"
            || lower == "application/yaml"
            || lower == "application/sql"
            || lower.hasSuffix("+json")
            || lower.hasSuffix("+xml")
        guard isText, let text = String(data: data, encoding: .utf8) else { return nil }
        let limit = 200_000
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n… (файл обрезан)"
    }

    static func mimeType(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let map: [String: String] = [
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png",
            "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
            "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff",
            "pdf": "application/pdf",
            "txt": "text/plain", "md": "text/markdown", "csv": "text/csv",
            "json": "application/json", "xml": "application/xml",
            "html": "text/html", "htm": "text/html", "css": "text/css",
            "js": "application/javascript", "ts": "text/plain",
            "swift": "text/plain", "py": "text/plain", "rb": "text/plain",
            "java": "text/plain", "c": "text/plain", "cpp": "text/plain",
            "h": "text/plain", "sh": "text/plain", "yml": "application/yaml",
            "yaml": "application/yaml", "log": "text/plain",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "zip": "application/zip", "mp3": "audio/mpeg", "m4a": "audio/mp4",
            "wav": "audio/wav", "mp4": "video/mp4", "mov": "video/quicktime"
        ]
        if let value = map[ext] { return value }
        return ext.isEmpty ? "application/octet-stream" : "application/" + ext
    }
}

/// Одно сообщение в диалоге.
struct ChatMessage: Codable, Equatable {
    var id: UUID
    var role: MessageRole
    var text: String
    var createdAt: Date
    var isError: Bool
    var modelName: String?
    var attachments: [ChatAttachment]

    init(id: UUID = UUID(),
         role: MessageRole,
         text: String,
         createdAt: Date = Date(),
         isError: Bool = false,
         modelName: String? = nil,
         attachments: [ChatAttachment] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isError = isError
        self.modelName = modelName
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text, createdAt, isError, modelName, attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decodeIfPresent(MessageRole.self, forKey: .role) ?? .assistant
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
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
        guard let last = messages.last(where: {
            !$0.text.isEmpty || !$0.attachments.isEmpty
        }) else { return "Пустой диалог" }

        let flattened = last.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flattened.isEmpty, let attachment = last.attachments.first {
            let prefix = attachment.isImage ? "📷 " : "📎 "
            return prefix + attachment.name
        }
        if flattened.count <= 90 { return flattened }
        return String(flattened.prefix(90)) + "…"
    }

    func messagesForRequest() -> [ChatMessage] {
        return messages.filter { message in
            !message.isError &&
            (!message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !message.attachments.isEmpty)
        }
    }
}
