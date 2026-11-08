import UIKit

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let cellIdentifier = "SettingsCell"

    private var providers: [ProviderConfig] {
        return AppSettings.shared.providers
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Настройки"
        view.backgroundColor = Theme.background

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.background
        tableView.rowHeight = 60
        tableView.separatorColor = Theme.separator
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(settingsChanged),
                                               name: AppSettings.didChangeNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func settingsChanged() {
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return providers.count + 1
        }
        return 3
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "ПРОВАЙДЕРЫ" : "СПРАВКА"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return "Ключи и токены аккаунтов хранятся только на этом устройстве. Вход в DeepSeek и Gemini выполняется на настоящих сайтах провайдеров."
        }
        return "UniChat 1.1 · iOS 12+ · без аналитики и без собственного сервера."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellIdentifier)

        cell.backgroundColor = Theme.card
        cell.textLabel?.textColor = Theme.primaryText
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.accessoryType = .disclosureIndicator
        cell.detailTextLabel?.numberOfLines = 1
        cell.detailTextLabel?.lineBreakMode = .byTruncatingTail

        if indexPath.section == 0 {
            if indexPath.row < providers.count {
                let provider = providers[indexPath.row]
                cell.textLabel?.text = provider.name
                cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)

                if provider.kind.isAccount {
                    cell.detailTextLabel?.text = provider.accountStatusText
                    cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
                    cell.detailTextLabel?.textColor = provider.isReady ? Theme.accent : Theme.danger
                } else {
                    var detail = "\(provider.kind.shortTitle) · \(provider.model)"
                    if provider.trimmedAPIKey.isEmpty {
                        detail += "  ·  нет ключа"
                    }
                    cell.detailTextLabel?.text = detail
                    cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
                    cell.detailTextLabel?.textColor = provider.trimmedAPIKey.isEmpty ? Theme.danger : Theme.secondaryText
                }
            } else {
                cell.textLabel?.text = "Добавить провайдера"
                cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
                cell.textLabel?.textColor = Theme.accent
                cell.detailTextLabel?.text = "API-ключ или вход в аккаунт"
                cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
                cell.accessoryType = .none
                cell.backgroundColor = Theme.card
            }
        } else {
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15)
            cell.textLabel?.textColor = Theme.primaryText
            cell.detailTextLabel?.text = nil
            cell.detailTextLabel?.textColor = Theme.secondaryText

            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Как получить бесплатные ключи"
            case 1:
                cell.textLabel?.text = "Gemini и работа в РФ"
            default:
                cell.textLabel?.text = "О приложении"
            }
        }

        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            if indexPath.row < providers.count {
                let provider = providers[indexPath.row]
                let editor = ProviderEditorViewController(provider: provider, isNew: false)
                navigationController?.pushViewController(editor, animated: true)
            } else {
                showAddProviderMenu(sourceView: tableView.cellForRow(at: indexPath))
            }
            return
        }

        let topic: InfoViewController.Topic
        switch indexPath.row {
        case 0: topic = .keys
        case 1: topic = .russia
        default: topic = .about
        }
        navigationController?.pushViewController(InfoViewController(topic: topic), animated: true)
    }

    private func showAddProviderMenu(sourceView: UIView?) {
        let alert = UIAlertController(title: "Тип провайдера", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "DeepSeek — вход в аккаунт", style: .default) { _ in
            let provider = ProviderConfig(
                name: "DeepSeek (аккаунт)",
                kind: .deepSeekAccount,
                baseURL: "https://chat.deepseek.com",
                model: "deepseek-chat",
                modelPresets: ["deepseek-chat", "deepseek-reasoner"]
            )
            self.openEditor(with: provider)
        })

        alert.addAction(UIAlertAction(title: "Gemini — вход в аккаунт", style: .default) { _ in
            let provider = ProviderConfig(
                name: "Gemini (аккаунт)",
                kind: .geminiAccount,
                baseURL: "https://gemini.google.com",
                model: "gemini-flash",
                modelPresets: ["gemini-flash", "gemini-pro", "gemini-flash-lite", "auto"]
            )
            self.openEditor(with: provider)
        })

        alert.addAction(UIAlertAction(title: "OpenAI-совместимый", style: .default) { _ in
            let provider = ProviderConfig(
                name: "Свой API",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o-mini",
                modelPresets: ["gpt-4o-mini", "gpt-4o"]
            )
            self.openEditor(with: provider)
        })

        alert.addAction(UIAlertAction(title: "Google Gemini — API-ключ", style: .default) { _ in
            let provider = ProviderConfig(
                name: "Gemini (свой)",
                kind: .gemini,
                baseURL: "https://generativelanguage.googleapis.com",
                model: "gemini-2.5-flash",
                modelPresets: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
            )
            self.openEditor(with: provider)
        })

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true, completion: nil)
    }

    private func openEditor(with provider: ProviderConfig) {
        let editor = ProviderEditorViewController(provider: provider, isNew: true)
        navigationController?.pushViewController(editor, animated: true)
    }
}
