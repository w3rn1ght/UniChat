import UIKit

final class ProviderEditorViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    UITextFieldDelegate, UITextViewDelegate {

    private var draft: ProviderConfig
    private let isNew: Bool
    private let tableView = UITableView(frame: .zero, style: .plain)

    private var nameField: UITextField?
    private var baseField: UITextField?
    private var modelField: UITextField?
    private var keyField: UITextField?
    private var systemTextView: UITextView?
    private var headersTextView: UITextView?

    private var pendingKey = ""
    private var isTesting = false
    private var isSaving = false
    private var wasDeleted = false

    private let textFieldTagName = 100
    private let textFieldTagBase = 102
    private let textFieldTagModel = 103
    private let textFieldTagKey = 104
    private let textViewTagSystem = 200
    private let textViewTagHeaders = 201

    init(provider: ProviderConfig, isNew: Bool) {
        self.draft = provider
        self.isNew = isNew
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = isNew ? "Новый провайдер" : draft.name
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.surface

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(saveTapped))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.surface
        tableView.separatorStyle = .none
        tableView.tableFooterView = UIView()
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        autoLoadModelsIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            if !wasDeleted {
                save(silent: true)
            }
        }
    }

    // MARK: - UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return draft.kind.isAccount ? 4 : 5
        case 1: return 3
        default: return isNew ? 1 : 2
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 1 {
            return indexPath.row == 0 ? 76 : 122
        }
        if indexPath.section == 2 {
            return 62
        }
        return 64
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 38
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return section == 1 ? 84 : 0.01
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        container.backgroundColor = Theme.surface

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        switch section {
        case 0: label.text = "ОСНОВНОЕ"
        case 1: label.text = "МОДЕЛИ И ПОВЕДЕНИЕ"
        default: label.text = "ПОДКЛЮЧЕНИЕ"
        }
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.accent
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 1 else { return nil }

        let container = UIView()
        container.backgroundColor = Theme.surface

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Theme.secondaryText
        label.text = "Список моделей загружается с сервера провайдера. Системный промпт задаёт поведение модели. Доп. заголовки — по одному на строку в формате «Key: Value» (OpenRouter: HTTP-Referer, X-Title)."
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                return makeTextFieldCell(title: "Название",
                                         text: draft.name,
                                         placeholder: "Например, OpenRouter",
                                         tag: textFieldTagName,
                                         secure: false)
            case 1:
                return makeValueCell(title: "Тип", value: draft.kind.shortTitle)
            default:
                break
            }

            if draft.kind.isAccount {
                if indexPath.row == 2 {
                    return makeTextFieldCell(title: "Модель",
                                             text: draft.model,
                                             placeholder: "gemini-flash",
                                             tag: textFieldTagModel,
                                             secure: false)
                }
                return makeAccountCell()
            }

            if indexPath.row == 2 {
                return makeTextFieldCell(title: "Base URL",
                                         text: draft.baseURL,
                                         placeholder: "https://…",
                                         tag: textFieldTagBase,
                                         secure: false)
            }

            if indexPath.row == 3 {
                return makeTextFieldCell(title: "Модель",
                                         text: draft.model,
                                         placeholder: draft.model.isEmpty
                                            ? "Загрузится автоматически"
                                            : "gpt-4o-mini",
                                         tag: textFieldTagModel,
                                         secure: false)
            }

            let placeholder = draft.hasAPIKey ? "Ключ сохранён — введите новый" : "Вставьте API-ключ"
            return makeTextFieldCell(title: "API-ключ",
                                     text: pendingKey,
                                     placeholder: placeholder,
                                     tag: textFieldTagKey,
                                     secure: true)
        }

        if indexPath.section == 1 {
            if indexPath.row == 0 {
                return makeModelsCell()
            }
            if indexPath.row == 1 {
                return makeTextViewCell(title: "Системный промпт",
                                        text: draft.systemPrompt,
                                        tag: textViewTagSystem)
            }
            return makeTextViewCell(title: "Доп. заголовки",
                                    text: ProviderEditorViewController.serializeHeaders(draft.extraHeaders),
                                    tag: textViewTagHeaders)
        }

        if indexPath.row == 0 {
            let cell = MaterialActionCell(style: .default, reuseIdentifier: nil)
            cell.configure(title: isTesting ? "Проверяем…" : "Проверить подключение",
                           color: Theme.accent)
            if isTesting {
                let spinner = UIActivityIndicatorView(style: .gray)
                spinner.startAnimating()
                spinner.translatesAutoresizingMaskIntoConstraints = false
                cell.cardView.addSubview(spinner)
                NSLayoutConstraint.activate([
                    spinner.trailingAnchor.constraint(equalTo: cell.cardView.trailingAnchor, constant: -20),
                    spinner.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor)
                ])
            }
            return cell
        }

        let cell = MaterialActionCell(style: .default, reuseIdentifier: nil)
        cell.configure(title: "Удалить провайдера", color: Theme.danger)
        return cell
    }

    // MARK: - Cells

    private func makeTextFieldCell(title: String,
                                   text: String,
                                   placeholder: String,
                                   tag: Int,
                                   secure: Bool) -> UITableViewCell {
        let cell = CardCell(style: .default, reuseIdentifier: nil)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = Theme.secondaryText
        cell.cardView.addSubview(label)

        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.tag = tag
        field.text = text
        field.placeholder = placeholder
        field.font = UIFont.systemFont(ofSize: 15)
        field.textColor = Theme.primaryText
        field.backgroundColor = Theme.surfaceContainer
        field.layer.cornerRadius = 10
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
        field.isSecureTextEntry = secure
        field.delegate = self
        field.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.leftViewMode = .always
        cell.cardView.addSubview(field)

        switch tag {
        case textFieldTagName: nameField = field
        case textFieldTagBase: baseField = field
        case textFieldTagModel: modelField = field
        case textFieldTagKey: keyField = field
        default: break
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.cardView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 82),

            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: cell.cardView.trailingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 38)
        ])
        return cell
    }

    private func makeValueCell(title: String, value: String) -> UITableViewCell {
        let cell = CardCell(style: .default, reuseIdentifier: nil)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = Theme.secondaryText
        cell.cardView.addSubview(label)

        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = value
        valueLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        valueLabel.textColor = Theme.primaryText
        valueLabel.textAlignment = .right
        cell.cardView.addSubview(valueLabel)

        let chevron = UILabel()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.text = "›"
        chevron.font = UIFont.systemFont(ofSize: 24)
        chevron.textColor = Theme.outline
        cell.cardView.addSubview(chevron)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.cardView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: cell.cardView.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 18),

            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
            valueLabel.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor)
        ])
        return cell
    }

    private func makeAccountCell() -> UITableViewCell {
        let cell = CardCell(style: .default, reuseIdentifier: nil)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Аккаунт"
        title.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        title.textColor = Theme.secondaryText
        cell.cardView.addSubview(title)

        let value = UILabel()
        value.translatesAutoresizingMaskIntoConstraints = false
        value.text = draft.accountStatusText
        value.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        value.textColor = draft.isReady ? Theme.success : Theme.danger
        value.textAlignment = .right
        cell.cardView.addSubview(value)

        let chevron = UILabel()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.text = "›"
        chevron.font = UIFont.systemFont(ofSize: 24)
        chevron.textColor = Theme.outline
        cell.cardView.addSubview(chevron)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.cardView.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: cell.cardView.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 18),

            value.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            value.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
            value.centerYAnchor.constraint(equalTo: cell.cardView.centerYAnchor)
        ])
        return cell
    }

    private func makeModelsCell() -> UITableViewCell {
        let cell = MaterialRowCell(style: .default, reuseIdentifier: nil)
        let badgeText = draft.kind == .deepSeekAccount ? "D"
            : (draft.kind == .geminiAccount ? "G" : "✦")
        let subtitle: String
        if ModelCatalog.supportsDiscovery(draft.kind) {
            if draft.modelPresets.isEmpty {
                subtitle = "Список загрузится автоматически"
            } else {
                subtitle = "\(draft.modelPresets.count) в списке · автопоиск доступен"
            }
        } else {
            subtitle = "\(draft.modelPresets.count) моделей аккаунта"
        }
        cell.configure(badgeText: badgeText,
                       badgeBackground: Theme.primaryContainer,
                       badgeForeground: Theme.onPrimaryContainer,
                       title: "Модели",
                       subtitle: subtitle,
                       accessory: nil,
                       showsChevron: true)
        return cell
    }

    private func makeTextViewCell(title: String, text: String, tag: Int) -> UITableViewCell {
        let cell = CardCell(style: .default, reuseIdentifier: nil)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.secondaryText
        cell.cardView.addSubview(label)

        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.tag = tag
        textView.text = text
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.textColor = Theme.primaryText
        textView.backgroundColor = Theme.surfaceContainer
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        cell.cardView.addSubview(textView)

        switch tag {
        case textViewTagSystem: systemTextView = textView
        case textViewTagHeaders: headersTextView = textView
        default: break
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.cardView.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: cell.cardView.topAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: cell.cardView.trailingAnchor, constant: -16),

            textView.leadingAnchor.constraint(equalTo: cell.cardView.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: cell.cardView.trailingAnchor, constant: -12),
            textView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 5),
            textView.bottomAnchor.constraint(equalTo: cell.cardView.bottomAnchor, constant: -9)
        ])
        return cell
    }

    // MARK: - Actions

    @objc private func textFieldChanged(_ field: UITextField) {
        switch field.tag {
        case textFieldTagName:
            draft.name = field.text ?? ""
        case textFieldTagBase:
            draft.baseURL = field.text ?? ""
        case textFieldTagModel:
            draft.model = field.text ?? ""
        case textFieldTagKey:
            pendingKey = field.text ?? ""
        default:
            break
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let text = textView.text ?? ""
        if textView.tag == textViewTagSystem {
            draft.systemPrompt = text
        } else if textView.tag == textViewTagHeaders {
            draft.extraHeaders = ProviderEditorViewController.parseHeaders(text)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            if indexPath.row == 1 {
                view.endEditing(true)
                applyFields()
                showTypeMenu(sourceView: tableView.cellForRow(at: indexPath))
                return
            }
            if draft.kind.isAccount && indexPath.row == 3 {
                openAccountLogin()
                return
            }
        }

        if indexPath.section == 1 && indexPath.row == 0 {
            view.endEditing(true)
            applyFields()
            AppSettings.shared.upsert(draft)
            openModelPicker()
            return
        }

        if indexPath.section == 2 {
            view.endEditing(true)
            if indexPath.row == 0 {
                runTest()
            } else {
                confirmDelete()
            }
        }
    }

    private func openModelPicker() {
        let picker = ModelPickerViewController(provider: draft,
                                               selectedModel: draft.model) { [weak self] model in
            guard let self = self else { return }
            self.draft.model = model
            self.modelField?.text = model
            if !self.draft.modelPresets.contains(model) {
                self.draft.modelPresets.insert(model, at: 0)
            }
            AppSettings.shared.addRecentModel(model, providerID: self.draft.id)
            AppSettings.shared.upsert(self.draft)
            self.tableView.reloadData()
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func openAccountLogin() {
        view.endEditing(true)
        applyFields()
        AppSettings.shared.upsert(draft)

        let controller = AccountLoginViewController(provider: draft) { [weak self] updated in
            guard let self = self else { return }
            self.draft = updated
            self.tableView.reloadData()
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func showTypeMenu(sourceView: UIView?) {
        let alert = UIAlertController(title: "Тип провайдера", message: nil, preferredStyle: .actionSheet)
        let kinds: [ProviderKind] = [.deepSeekAccount, .geminiAccount, .openAICompatible, .gemini]
        for kind in kinds {
            let mark = draft.kind == kind ? "✓ " : ""
            alert.addAction(UIAlertAction(title: mark + kind.title, style: .default) { _ in
                self.changeKind(to: kind)
            })
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true, completion: nil)
    }

    private func changeKind(to kind: ProviderKind) {
        guard kind != draft.kind else { return }
        draft.kind = kind
        baseField = nil
        keyField = nil

        switch kind {
        case .deepSeekAccount:
            draft.baseURL = "https://chat.deepseek.com"
            draft.modelPresets = ["deepseek-chat", "deepseek-reasoner"]
            if draft.model.isEmpty || !draft.modelPresets.contains(draft.model) {
                draft.model = "deepseek-chat"
            }
            draft.accountConnected = !draft.trimmedAccountToken.isEmpty

        case .geminiAccount:
            draft.baseURL = "https://gemini.google.com"
            draft.modelPresets = ["gemini-flash", "gemini-pro", "gemini-flash-lite", "auto"]
            if draft.model.isEmpty || !draft.modelPresets.contains(draft.model) {
                draft.model = "gemini-flash"
            }

        case .gemini:
            draft.baseURL = "https://generativelanguage.googleapis.com"
            draft.modelPresets = []
            draft.model = ""

        case .openAICompatible:
            if draft.baseURL == "https://chat.deepseek.com" || draft.baseURL == "https://gemini.google.com" {
                draft.baseURL = "https://api.openai.com/v1"
            }
            draft.modelPresets = []
            draft.model = ""
        }

        tableView.reloadData()
    }

    private func applyFields() {
        if let nameField = nameField { draft.name = nameField.text ?? draft.name }
        if let modelField = modelField { draft.model = modelField.text ?? draft.model }

        if draft.kind.isAccount {
            pendingKey = ""
        } else {
            if let baseField = baseField { draft.baseURL = baseField.text ?? draft.baseURL }
            if let keyField = keyField { pendingKey = keyField.text ?? pendingKey }
        }

        if let systemTextView = systemTextView { draft.systemPrompt = systemTextView.text }
        if let headersTextView = headersTextView {
            draft.extraHeaders = ProviderEditorViewController.parseHeaders(headersTextView.text)
        }

        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)

        if !draft.kind.isAccount && !pendingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.apiKey = pendingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        save(silent: false)
    }

    private func save(silent: Bool) {
        guard !isSaving else { return }
        applyFields()

        guard !draft.name.isEmpty else {
            if !silent { showAlert(title: "Нужно название", message: "Введите название провайдера.") }
            return
        }
        guard !draft.baseURL.isEmpty else {
            if !silent { showAlert(title: "Нужен Base URL", message: "Введите адрес API.") }
            return
        }

        if !draft.model.isEmpty {
            persistAndClose(silent: silent)
            return
        }

        // Модель вводить не обязательно: пробуем загрузить список сам.
        if silent {
            draft.model = draft.modelPresets.first ?? ""
            AppSettings.shared.upsert(draft)
            return
        }

        guard ModelCatalog.supportsDiscovery(draft.kind) else {
            draft.model = defaultModel(for: draft.kind)
            guard !draft.model.isEmpty else {
                showAlert(title: "Нужна модель", message: "Введите название модели.")
                return
            }
            persistAndClose(silent: false)
            return
        }

        guard draft.kind == .openAICompatible || draft.hasAPIKey else {
            showAlert(title: "Нужен ключ",
                      message: "Вставьте API-ключ — приложение само загрузит список моделей.")
            return
        }

        isSaving = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.rightBarButtonItem?.title = "Загрузка…"

        ModelCatalog.fetch(for: draft) { [weak self] result in
            guard let self = self else { return }
            self.isSaving = false
            self.navigationItem.rightBarButtonItem?.isEnabled = true
            self.navigationItem.rightBarButtonItem?.title = "Сохранить"

            switch result {
            case .success(let models) where !models.isEmpty:
                self.draft.modelPresets = ModelCatalog.merged(models, with: self.draft)
                self.draft.model = models[0]
                self.modelField?.text = self.draft.model
                AppSettings.shared.addRecentModel(self.draft.model, providerID: self.draft.id)
                AnyModelCatalog.refresh(for: self.draft)
                self.persistAndClose(silent: false)
            case .failure(let error):
                if self.view.window != nil {
                    self.showAlert(title: "Не удалось получить модели",
                                   message: error.localizedDescription + "\nПроверьте Base URL и ключ.")
                }
            default:
                if self.view.window != nil {
                    self.showAlert(title: "Список моделей пуст",
                                   message: "Проверьте Base URL и ключ. Модель можно ввести вручную.")
                }
            }
        }
    }

    private func persistAndClose(silent: Bool) {
        AppSettings.shared.upsert(draft)
        if !silent, navigationController?.topViewController === self {
            navigationController?.popViewController(animated: true)
        }
    }

    private func defaultModel(for kind: ProviderKind) -> String {
        switch kind {
        case .deepSeekAccount: return "deepseek-chat"
        case .geminiAccount: return "gemini-flash"
        case .gemini: return "gemini-2.5-flash"
        case .openAICompatible: return ""
        }
    }

    /// Тихо подтягивает модели при открытии провайдера, если их ещё нет.
    private func autoLoadModelsIfNeeded() {
        guard ModelCatalog.supportsDiscovery(draft.kind) else { return }
        guard draft.kind == .openAICompatible || draft.hasAPIKey else { return }
        guard draft.modelPresets.isEmpty || draft.model.isEmpty else { return }

        ModelCatalog.fetch(for: draft) { [weak self] result in
            guard let self = self, case .success(let models) = result, !models.isEmpty else { return }
            self.draft.modelPresets = ModelCatalog.merged(models, with: self.draft)
            if self.draft.model.isEmpty {
                self.draft.model = models[0]
            }
            self.modelField?.text = self.draft.model
            AppSettings.shared.upsert(self.draft)
            AnyModelCatalog.refresh(for: self.draft)
            self.tableView.reloadData()
        }
    }

    private func runTest() {
        applyFields()

        if draft.kind.isAccount {
            guard draft.isReady else {
                showAlert(title: "Нужен вход",
                          message: "Сначала войдите в аккаунт: нажмите строку «Аккаунт».")
                return
            }
        } else {
            guard !draft.baseURL.isEmpty else {
                showAlert(title: "Нужен Base URL", message: "Введите адрес API.")
                return
            }
            guard draft.hasAPIKey else {
                showAlert(title: "Нужен ключ", message: "Вставьте API-ключ, чтобы проверить подключение.")
                return
            }
        }

        isTesting = true
        tableView.reloadSections(IndexSet(integer: 2), with: .none)

        AppSettings.shared.upsert(draft)
        let provider = ProviderFactory.make(for: draft)
        provider.testConnection { [weak self] result in
            guard let self = self else { return }
            self.isTesting = false

            if let latest = AppSettings.shared.provider(id: self.draft.id) {
                self.draft = latest
            }
            self.tableView.reloadData()

            switch result {
            case .success(let message):
                self.showAlert(title: "Успешно", message: message)
                self.loadModelsAfterTest()
            case .failure(let error):
                self.showAlert(title: "Не удалось", message: error.localizedDescription)
            }
        }
    }

    private func loadModelsAfterTest() {
        guard ModelCatalog.supportsDiscovery(draft.kind) else { return }
        ModelCatalog.fetch(for: draft) { [weak self] result in
            guard let self = self, case .success(let models) = result, !models.isEmpty else { return }
            var merged = models
            if !self.draft.model.isEmpty && !merged.contains(self.draft.model) {
                merged.insert(self.draft.model, at: 0)
            }
            self.draft.modelPresets = merged
            if self.draft.model.isEmpty {
                self.draft.model = merged[0]
                self.modelField?.text = self.draft.model
                AppSettings.shared.addRecentModel(self.draft.model, providerID: self.draft.id)
            }
            AppSettings.shared.upsert(self.draft)
            self.tableView.reloadData()
        }
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "Удалить провайдера?",
                                      message: "Ключ будет удалён из Keychain.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { _ in
            self.wasDeleted = true
            AppSettings.shared.remove(id: self.draft.id)
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true, completion: nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Headers

    private static func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    private static func serializeHeaders(_ headers: [String: String]) -> String {
        return headers
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\n")
    }
}
