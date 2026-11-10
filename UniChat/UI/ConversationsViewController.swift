import UIKit

final class ConversationsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let emptyBadge = CircleBadgeView()
    private let fab = UIButton(type: .custom)
    private let cellIdentifier = "ConversationCell"
    private static var didRefreshModels = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Чаты"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = Theme.surface

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Настройки",
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(openSettings))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.surface
        tableView.separatorStyle = .none
        tableView.tableFooterView = UIView()
        tableView.rowHeight = 86
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 96, right: 0)
        view.addSubview(tableView)

        let longPress = UILongPressGestureRecognizer(target: self,
                                                     action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        tableView.addGestureRecognizer(longPress)

        emptyBadge.configure(text: "✦",
                             background: Theme.primaryContainer,
                             foreground: Theme.onPrimaryContainer,
                             fontSize: 30)
        view.addSubview(emptyBadge)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Пока нет чатов\nНажмите +, чтобы начать"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.textColor = Theme.secondaryText
        view.addSubview(emptyLabel)

        fab.translatesAutoresizingMaskIntoConstraints = false
        fab.setTitle("+", for: .normal)
        fab.setTitleColor(Theme.onPrimaryContainer, for: .normal)
        fab.titleLabel?.font = UIFont.systemFont(ofSize: 30, weight: .medium)
        fab.backgroundColor = Theme.primaryContainer
        fab.layer.cornerRadius = 28
        if #available(iOS 13.0, *) {
            fab.layer.cornerCurve = .continuous
        }
        Theme.applyShadow(fab, opacity: 0.16, radius: 12, offset: CGSize(width: 0, height: 6))
        fab.addTarget(self, action: #selector(createChat), for: .touchUpInside)
        view.addSubview(fab)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyBadge.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyBadge.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -70),
            emptyBadge.widthAnchor.constraint(equalToConstant: 72),
            emptyBadge.heightAnchor.constraint(equalToConstant: 72),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: emptyBadge.bottomAnchor, constant: 18),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            fab.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -22),
            fab.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),
            fab.widthAnchor.constraint(equalToConstant: 56),
            fab.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Один раз за запуск тихо обновляем списки моделей у готовых провайдеров.
        if !ConversationsViewController.didRefreshModels {
            ConversationsViewController.didRefreshModels = true
            ModelCatalog.refreshAll(AppSettings.shared.providers)
            for provider in AppSettings.shared.providers {
                AnyModelCatalog.refresh(for: provider)
            }
        }
    }

    private func updateEmptyState() {
        let isEmpty = ConversationStore.shared.conversations.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyBadge.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    // MARK: - Actions

    @objc private func openSettings() {
        let controller = SettingsViewController()
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func createChat() {
        let settings = AppSettings.shared
        var provider = settings.provider(id: settings.lastProviderID)
        if provider == nil { provider = settings.firstProvider() }

        guard let selected = provider else {
            let alert = UIAlertController(title: "Нет провайдеров",
                                          message: "Добавьте хотя бы одного провайдера в настройках.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Настройки", style: .default, handler: { _ in
                self.openSettings()
            }))
            present(alert, animated: true, completion: nil)
            return
        }

        var conversation = Conversation()
        conversation.providerID = selected.id
        conversation.model = settings.lastModel(for: selected.id) ?? selected.model
        ConversationStore.shared.add(conversation)

        let chat = ChatViewController(conversation: conversation)
        navigationController?.pushViewController(chat, animated: true)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ConversationStore.shared.conversations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) as? MaterialRowCell
            ?? MaterialRowCell(style: .default, reuseIdentifier: cellIdentifier)

        let conversation = ConversationStore.shared.conversations[indexPath.row]
        let provider = AppSettings.shared.provider(id: conversation.providerID)
        let providerName = provider?.name ?? "нет провайдера"
        let model = conversation.model ?? "—"
        let letter = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1).uppercased()
        let badgeText: String = letter.isEmpty ? "✦" : letter

        cell.configure(badgeText: badgeText,
                       badgeBackground: Theme.toneColor(for: indexPath.row),
                       badgeForeground: Theme.primaryText,
                       title: conversation.title,
                       subtitle: "\(providerName) · \(model)",
                       accessory: Theme.dateString(conversation.updatedAt),
                       showsChevron: true)
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let conversation = ConversationStore.shared.conversations[indexPath.row]
        let chat = ChatViewController(conversation: conversation)
        navigationController?.pushViewController(chat, animated: true)
    }

    // MARK: - Удаление и переименование

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              indexPath.row < ConversationStore.shared.conversations.count else { return }

        let conversation = ConversationStore.shared.conversations[indexPath.row]
        let alert = UIAlertController(title: conversation.title,
                                      message: nil,
                                      preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Переименовать", style: .default) { _ in
            self.promptRename(id: conversation.id)
        })
        alert.addAction(UIAlertAction(title: "Удалить чат", style: .destructive) { _ in
            self.confirmDelete(id: conversation.id)
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))

        alert.popoverPresentationController?.sourceView = tableView
        alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        present(alert, animated: true, completion: nil)
    }

    private func promptRename(id: UUID) {
        guard let conversation = ConversationStore.shared.conversation(id: id) else { return }

        let alert = UIAlertController(title: "Название чата", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = conversation.title
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
            let value = (alert.textFields?.first?.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }

            if var updated = ConversationStore.shared.conversation(id: id) {
                updated.title = value
                updated.updatedAt = Date()
                ConversationStore.shared.update(updated)
                self.tableView.reloadData()
            }
        })
        present(alert, animated: true, completion: nil)
    }

    private func confirmDelete(id: UUID) {
        guard let conversation = ConversationStore.shared.conversation(id: id) else { return }

        let alert = UIAlertController(title: "Удалить чат?",
                                      message: "«\(conversation.title)» и вся история сообщений будут удалены.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { _ in
            ConversationStore.shared.delete(id: id)
            self.tableView.reloadData()
            self.updateEmptyState()
        })
        present(alert, animated: true, completion: nil)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let conversation = ConversationStore.shared.conversations[indexPath.row]
        ConversationStore.shared.delete(id: conversation.id)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        updateEmptyState()
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.row < ConversationStore.shared.conversations.count else { return nil }
        let id = ConversationStore.shared.conversations[indexPath.row].id

        let delete = UIContextualAction(style: .destructive, title: "Удалить") { _, _, completion in
            self.confirmDelete(id: id)
            completion(true)
        }

        let rename = UIContextualAction(style: .normal, title: "Название") { _, _, completion in
            self.promptRename(id: id)
            completion(true)
        }
        rename.backgroundColor = Theme.accent

        let config = UISwipeActionsConfiguration(actions: [delete, rename])
        config.performsFirstActionWithFullSwipe = false
        return config
    }
}
