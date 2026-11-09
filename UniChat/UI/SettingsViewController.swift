import UIKit

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let cellIdentifier = "SettingsMaterialCell"

    private var providers: [ProviderConfig] {
        return AppSettings.shared.providers
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Настройки"
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = Theme.surface

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.surface
        tableView.separatorStyle = .none
        tableView.tableFooterView = UIView()
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
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
        return "UniChat 1.2 · iOS 12+ · Material You · без аналитики и собственного сервера."
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return indexPath.section == 0 ? 86 : 80
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        container.backgroundColor = Theme.surface

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = section == 0 ? "ПРОВАЙДЕРЫ" : "СПРАВКА"
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.accent
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 38
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        if let footer = view as? UITableViewHeaderFooterView {
            footer.textLabel?.font = UIFont.systemFont(ofSize: 11)
            footer.textLabel?.textColor = Theme.secondaryText
            footer.contentView.backgroundColor = Theme.surface
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier) as? MaterialRowCell
            ?? MaterialRowCell(style: .default, reuseIdentifier: cellIdentifier)

        if indexPath.section == 0 {
            if indexPath.row < providers.count {
                let provider = providers[indexPath.row]
                let badgeText: String
                switch provider.kind {
                case .deepSeekAccount: badgeText = "D"
                case .geminiAccount: badgeText = "G"
                case .gemini: badgeText = "✦"
                case .openAICompatible: badgeText = "◈"
                }

                var subtitle = provider.kind.shortTitle + " · " + provider.model
                var accessory: String?
                if provider.kind.isAccount {
                    subtitle = provider.accountStatusText
                    accessory = provider.isReady ? "Готов" : "Войти"
                } else {
                    if provider.trimmedAPIKey.isEmpty {
                        subtitle = provider.kind.shortTitle + " · " + provider.model + " · нет ключа"
                        accessory = "Нет ключа"
                    } else {
                        accessory = "Готов"
                    }
                }

                cell.configure(badgeText: badgeText,
                               badgeBackground: Theme.toneColor(for: indexPath.row),
                               badgeForeground: Theme.primaryText,
                               title: provider.name,
                               subtitle: subtitle,
                               accessory: accessory,
                               titleColor: Theme.primaryText,
                               showsChevron: true)
                cell.accessoryView = nil
            } else {
                cell.configure(badgeText: "+",
                               badgeBackground: Theme.secondaryContainer,
                               badgeForeground: Theme.onSecondaryContainer,
                               badgeFontSize: 20,
                               title: "Добавить провайдера",
                               subtitle: "API-ключ или вход в аккаунт",
                               accessory: nil,
                               titleColor: Theme.accent,
                               showsChevron: true)
            }
            return cell
        }

        let badges = ["?", "↗", "i"]
        let titles = ["Как получить бесплатные ключи", "Gemini и работа в РФ", "О приложении"]
        let subtitles = ["Инструкции по ключам и аккаунтам", "VPN, релей или OpenRouter", "Версия, принципы, ограничения"]
        cell.configure(badgeText: badges[indexPath.row],
                       badgeBackground: Theme.toneColor(for: indexPath.row + 2),
                       badgeForeground: Theme.primaryText,
                       title: titles[indexPath.row],
                       subtitle: subtitles[indexPath.row],
                       accessory: nil,
                       showsChevron: true)
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

        alert.addAction(UIAlertAction(title: "OpenAI-совместимый API", style: .default) { _ in
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
