import UIKit

final class ConversationsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let cellIdentifier = "ConversationCell"

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Чаты"
        view.backgroundColor = Theme.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Настройки",
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(openSettings))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                            target: self,
                                                            action: #selector(createChat))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.separator
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.tableFooterView = UIView()
        tableView.rowHeight = 72
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Пока нет чатов\nНажмите +, чтобы начать"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.textColor = Theme.secondaryText
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        let isEmpty = ConversationStore.shared.conversations.isEmpty
        emptyLabel.isHidden = !isEmpty
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
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellIdentifier)

        let conversation = ConversationStore.shared.conversations[indexPath.row]
        cell.textLabel?.text = conversation.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        cell.textLabel?.textColor = Theme.primaryText

        let providerName = AppSettings.shared.provider(id: conversation.providerID)?.name ?? "нет провайдера"
        let model = conversation.model ?? "—"
        cell.detailTextLabel?.text = "\(providerName) · \(model) · \(Theme.dateString(conversation.updatedAt))"
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.detailTextLabel?.lineBreakMode = .byTruncatingTail

        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = Theme.card
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let conversation = ConversationStore.shared.conversations[indexPath.row]
        let chat = ChatViewController(conversation: conversation)
        navigationController?.pushViewController(chat, animated: true)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let conversation = ConversationStore.shared.conversations[indexPath.row]
        ConversationStore.shared.delete(id: conversation.id)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        updateEmptyState()
    }
}
