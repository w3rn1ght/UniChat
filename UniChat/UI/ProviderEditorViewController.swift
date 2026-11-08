import UIKit

final class ProviderEditorViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    UITextFieldDelegate, UITextViewDelegate {

    private var draft: ProviderConfig
    private let isNew: Bool
    private let tableView = UITableView(frame: .zero, style: .grouped)

    private var nameField: UITextField?
    private var baseField: UITextField?
    private var modelField: UITextField?
    private var keyField: UITextField?
    private var systemTextView: UITextView?
    private var headersTextView: UITextView?

    private var pendingKey = ""
    private var isTesting = false
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
        view.backgroundColor = Theme.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(saveTapped))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.separator
        tableView.tableFooterView = UIView()
        tableView.keyboardDismissMode = .interactive
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        case 0: return 5
        case 1: return 2
        default: return isNew ? 1 : 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "ОСНОВНОЕ"
        case 1: return "ДОПОЛНИТЕЛЬНО"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 {
            return "Системный промпт задаёт поведение модели.\nДоп. заголовки — по одному на строку в формате «Key: Value». Нужны для OpenRouter (HTTP-Referer, X-Title) и кастомных шлюзов."
        }
        return nil
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 1 { return 116 }
        return 48
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                let cell = makeTextFieldCell(title: "Название",
                                             text: draft.name,
                                             placeholder: "Например, OpenRouter",
                                             tag: textFieldTagName,
                                             secure: false)
                nameField = cell.contentView.viewWithTag(textFieldTagName) as? UITextField
                return cell
            case 1:
                return makeTypeCell()
            case 2:
                let cell = makeTextFieldCell(title: "Base URL",
                                             text: draft.baseURL,
                                             placeholder: "https://…",
                                             tag: textFieldTagBase,
                                             secure: false)
                baseField = cell.contentView.viewWithTag(textFieldTagBase) as? UITextField
                return cell
            case 3:
                let cell = makeTextFieldCell(title: "Модель",
                                             text: draft.model,
                                             placeholder: "gemini-2.5-flash",
                                             tag: textFieldTagModel,
                                             secure: false)
                modelField = cell.contentView.viewWithTag(textFieldTagModel) as? UITextField
                return cell
            default:
                let placeholder = draft.hasAPIKey ? "Ключ сохранён — введите новый" : "Вставьте API-ключ"
                let cell = makeTextFieldCell(title: "API-ключ",
                                             text: pendingKey,
                                             placeholder: placeholder,
                                             tag: textFieldTagKey,
                                             secure: true)
                keyField = cell.contentView.viewWithTag(textFieldTagKey) as? UITextField
                return cell
            }
        }

        if indexPath.section == 1 {
            if indexPath.row == 0 {
                let cell = makeTextViewCell(title: "Системный промпт",
                                            text: draft.systemPrompt,
                                            tag: textViewTagSystem)
                systemTextView = cell.contentView.viewWithTag(textViewTagSystem) as? UITextView
                return cell
            } else {
                let cell = makeTextViewCell(title: "Доп. заголовки",
                                            text: ProviderEditorViewController.serializeHeaders(draft.extraHeaders),
                                            tag: textViewTagHeaders)
                headersTextView = cell.contentView.viewWithTag(textViewTagHeaders) as? UITextView
                return cell
            }
        }

        if indexPath.row == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = Theme.card
            cell.textLabel?.text = isTesting ? "Проверяем…" : "Проверить подключение"
            cell.textLabel?.textColor = Theme.accent
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            cell.textLabel?.textAlignment = .center
            if isTesting {
                let spinner = UIActivityIndicatorView(style: .gray)
                spinner.startAnimating()
                cell.accessoryView = spinner
            }
            return cell
        }

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Theme.card
        cell.textLabel?.text = "Удалить провайдера"
        cell.textLabel?.textColor = Theme.danger
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        cell.textLabel?.textAlignment = .center
        return cell
    }

    // MARK: - Cells

    private func makeTextFieldCell(title: String,
                                   text: String,
                                   placeholder: String,
                                   tag: Int,
                                   secure: Bool) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Theme.card
        cell.selectionStyle = .none

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Theme.secondaryText
        cell.contentView.addSubview(label)

        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.tag = tag
        field.text = text
        field.placeholder = placeholder
        field.font = UIFont.systemFont(ofSize: 15)
        field.textColor = Theme.primaryText
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
        field.isSecureTextEntry = secure
        field.delegate = self
        field.addTarget(self, action: #selector(textFieldChanged(_:)), for: .editingChanged)
        cell.contentView.addSubview(field)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 92),

            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 36)
        ])
        return cell
    }

    private func makeTypeCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Theme.card
        cell.textLabel?.text = "Тип"
        cell.textLabel?.font = UIFont.systemFont(ofSize: 14)
        cell.textLabel?.textColor = Theme.secondaryText
        cell.detailTextLabel?.text = draft.kind.title
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 15)
        cell.detailTextLabel?.textColor = Theme.primaryText
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func makeTextViewCell(title: String, text: String, tag: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = Theme.card
        cell.selectionStyle = .none

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.secondaryText
        cell.contentView.addSubview(label)

        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.tag = tag
        textView.text = text
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.textColor = Theme.primaryText
        textView.backgroundColor = Theme.background
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        cell.contentView.addSubview(textView)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),

            textView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),
            textView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            textView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)
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
        if textView.tag == textViewTagSystem {
            draft.systemPrompt = textView.text
        } else if textView.tag == textViewTagHeaders {
            draft.extraHeaders = ProviderEditorViewController.parseHeaders(textView.text)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 && indexPath.row == 1 {
            view.endEditing(true)
            applyFields()
            showTypeMenu(sourceView: tableView.cellForRow(at: indexPath))
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

    private func showTypeMenu(sourceView: UIView?) {
        let alert = UIAlertController(title: "Тип провайдера", message: nil, preferredStyle: .actionSheet)
        for kind in [ProviderKind.openAICompatible, ProviderKind.gemini] {
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
        let wasGemini = draft.kind == .gemini
        draft.kind = kind

        let googleURL = "https://generativelanguage.googleapis.com"
        if kind == .gemini {
            if draft.baseURL.isEmpty || !wasGemini {
                draft.baseURL = googleURL
            }
            if draft.modelPresets.isEmpty {
                draft.modelPresets = ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
            }
            if draft.model.isEmpty {
                draft.model = "gemini-2.5-flash"
            }
        } else {
            if draft.baseURL.isEmpty || wasGemini {
                draft.baseURL = "https://api.openai.com/v1"
            }
            if draft.model.isEmpty {
                draft.model = "gpt-4o-mini"
            }
        }

        tableView.reloadData()
    }

    private func applyFields() {
        if let nameField = nameField { draft.name = nameField.text ?? draft.name }
        if let baseField = baseField { draft.baseURL = baseField.text ?? draft.baseURL }
        if let modelField = modelField { draft.model = modelField.text ?? draft.model }
        if let keyField = keyField {
            pendingKey = keyField.text ?? pendingKey
        }
        if let systemTextView = systemTextView { draft.systemPrompt = systemTextView.text }
        if let headersTextView = headersTextView {
            draft.extraHeaders = ProviderEditorViewController.parseHeaders(headersTextView.text)
        }

        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)

        if !pendingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.apiKey = pendingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        save(silent: false)
    }

    private func save(silent: Bool) {
        applyFields()

        guard !draft.name.isEmpty else {
            if !silent { showAlert(title: "Нужно название", message: "Введите название провайдера.") }
            return
        }
        guard !draft.baseURL.isEmpty else {
            if !silent { showAlert(title: "Нужен Base URL", message: "Введите адрес API.") }
            return
        }
        guard !draft.model.isEmpty else {
            if !silent { showAlert(title: "Нужна модель", message: "Введите название модели.") }
            return
        }

        AppSettings.shared.upsert(draft)
        if !silent {
            navigationController?.popViewController(animated: true)
        }
    }

    private func runTest() {
        applyFields()
        guard !draft.baseURL.isEmpty else {
            showAlert(title: "Нужен Base URL", message: "Введите адрес API.")
            return
        }
        guard draft.hasAPIKey else {
            showAlert(title: "Нужен ключ", message: "Вставьте API-ключ, чтобы проверить подключение.")
            return
        }

        isTesting = true
        tableView.reloadSections(IndexSet(integer: 2), with: .none)

        let provider = ProviderFactory.make(for: draft)
        provider.testConnection { [weak self] result in
            guard let self = self else { return }
            self.isTesting = false
            self.tableView.reloadSections(IndexSet(integer: 2), with: .none)

            switch result {
            case .success(let message):
                self.showAlert(title: "Успешно", message: message)
            case .failure(let error):
                self.showAlert(title: "Не удалось", message: error.localizedDescription)
            }
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
