import Foundation

/// Хранилище диалогов в Application Support.
final class ConversationStore {

    static let shared = ConversationStore()

    private(set) var conversations: [Conversation] = []

    private let ioQueue = DispatchQueue(label: "com.unichat.store.io", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    private lazy var directoryURL: URL = {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        return base.appendingPathComponent("UniChat", isDirectory: true)
    }()

    private lazy var fileURL: URL = {
        return directoryURL.appendingPathComponent("conversations.json")
    }()

    private init() {}

    // MARK: - Загрузка / сохранение

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            conversations = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([Conversation].self, from: data) else {
            conversations = []
            return
        }
        conversations = list.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Отложенное сохранение — используется во время стриминга.
    func saveSoon() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.save()
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: item)
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil

        let snapshot = conversations
        let directory = directoryURL
        let url = fileURL

        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Операции

    func conversation(id: UUID) -> Conversation? {
        return conversations.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        return conversations.firstIndex { $0.id == id }
    }

    func add(_ conversation: Conversation) {
        conversations.append(conversation)
        sort()
        saveSoon()
    }

    func update(_ conversation: Conversation) {
        var updated = conversation
        updated.updatedAt = Date()
        if let index = index(of: updated.id) {
            conversations[index] = updated
        } else {
            conversations.append(updated)
        }
        sort()
        saveSoon()
    }

    func delete(id: UUID) {
        conversations.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        conversations.removeAll()
        save()
    }

    private func sort() {
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }
}
