import UIKit

/// Единый список моделей всех провайдеров: поиск, недавние, группировка
/// по провайдерам и автоматическая подгрузка моделей с серверов.
final class ChatModelPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    UISearchBarDelegate {

    private struct Entry {
        let provider: ProviderConfig
        let model: String
        let isCustom: Bool

        init(provider: ProviderConfig, model: String, isCustom: Bool = false) {
            self.provider = provider
            self.model = model
            self.isCustom = isCustom
        }
    }

    private struct Section {
        let title: String
        let entries: [Entry]
    }

    private var providers: [ProviderConfig]
    private let selectedProviderID: UUID?
    private let selectedModel: String
    private let onSelect: (ProviderConfig, String) -> Void

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let footerLabel = UILabel()
    private let refreshControl = UIRefreshControl()

    private var sections: [Section] = []
    private var isLoading = false
    private var lastRefresh = Date.distantPast

    init(providers: [ProviderConfig],
         selectedProviderID: UUID?,
         selectedModel: String,
         onSelect: @escaping (ProviderConfig, String) -> Void) {
        self.providers = providers
        self.selectedProviderID = selectedProviderID
        self.selectedModel = selectedModel
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Модели"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.surface
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Ключи",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(openSettings))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.surface
        tableView.separatorStyle = .none
        tableView.rowHeight = 62
        tableView.sectionHeaderHeight = 34
        tableView.sectionFooterHeight = 0
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        setupHeader()
        setupFooter()

        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl

        rebuildSections()
        tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        providers = AppSettings.shared.providers
        rebuildSections()
        tableView.reloadData()
        loadAll()
    }

    // MARK: - UI

    private func setupHeader() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 58))
        container.backgroundColor = Theme.surface

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = "Поиск моделей"
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundImage = UIImage()
        searchBar.tintColor = Theme.accent
        searchBar.barTintColor = Theme.surface
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        container.addSubview(searchBar)

        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            searchBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            searchBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])

        tableView.tableHeaderView = container
    }

    private func setupFooter() {
        footerLabel.numberOfLines = 0
        footerLabel.textAlignment = .center
        footerLabel.font = UIFont.systemFont(ofSize: 11)
        footerLabel.textColor = Theme.secondaryText
        footerLabel.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 58)
        updateFooter()
        tableView.tableFooterView = footerLabel
    }

    private func updateFooter() {
        if isLoading {
            footerLabel.text = "Обновляем списки моделей…"
            return
        }
        let total = sections.reduce(0) { $0 + $1.entries.count }
        footerLabel.text = "Моделей: \(total). Списки загружаются автоматически; потяните вниз, чтобы обновить."
    }

    private func makeEmptyView() -> UIView {
        let container = UIView()

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = Theme.secondaryText
        label.text = "Пока нет моделей.\nДобавьте провайдера и ключ —\nсписок загрузится сам."
        container.addSubview(label)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Открыть настройки", for: .normal)
        button.setTitleColor(Theme.onPrimaryContainer, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.backgroundColor = Theme.primaryContainer
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        button.layer.cornerRadius = 18
        button.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -36),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),

            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 18),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        return container
    }

    // MARK: - Данные

    private func rebuildSections() {
        let query = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func matches(_ entry: Entry) -> Bool {
            guard !query.isEmpty else { return true }
            if entry.isCustom { return false }
            return entry.model.lowercased().contains(query)
                || entry.provider.name.lowercased().contains(query)
                || ChatModelPickerViewController.displayName(for: entry.model).lowercased().contains(query)
        }

        var result: [Section] = []

        // Недавние
        var recent: [Entry] = []
        for item in AppSettings.shared.recentModels() {
            guard let provider = providers.first(where: { $0.id == item.providerID }) else { continue }
            let known = item.model == provider.model || provider.modelPresets.contains(item.model)
            guard known else { continue }
            if recent.contains(where: { $0.provider.id == provider.id && $0.model == item.model }) {
                continue
            }
            recent.append(Entry(provider: provider, model: item.model))
        }
        let filteredRecent = recent.filter(matches)
        if !filteredRecent.isEmpty {
            result.append(Section(title: "Недавние", entries: filteredRecent))
        }

        // Провайдеры
        for provider in providers {
            var models = provider.modelPresets
            if !provider.model.isEmpty && !models.contains(provider.model) {
                models.insert(provider.model, at: 0)
            }
            var seen = Set<String>()
            models = models.filter { seen.insert($0).inserted }

            var entries = models.map { Entry(provider: provider, model: $0) }.filter(matches)
            if query.isEmpty {
                entries.append(Entry(provider: provider, model: "", isCustom: true))
            }
            guard !entries.isEmpty else { continue }

            let suffix = provider.isReady ? "" : " · нужен ключ"
            result.append(Section(title: provider.name + suffix, entries: entries))
        }

        sections = result
        tableView.backgroundView = result.isEmpty ? makeEmptyView() : nil
        updateFooter()
    }

    private func loadAll(force: Bool = false) {
        guard !isLoading else { return }
        if !force && Date().timeIntervalSince(lastRefresh) < 15 { return }

        let targets = providers.filter { provider in
            return ModelCatalog.supportsDiscovery(provider.kind) && provider.isReady
        }
        guard !targets.isEmpty else {
            refreshControl.endRefreshing()
            rebuildSections()
            tableView.reloadData()
            return
        }

        isLoading = true
        lastRefresh = Date()
        updateFooter()

        let group = DispatchGroup()
        var updates: [UUID: [String]] = [:]

        for provider in targets {
            group.enter()
            ModelCatalog.fetch(for: provider) { result in
                if case .success(let models) = result, !models.isEmpty {
                    updates[provider.id] = models
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.refreshControl.endRefreshing()

            self.providers = AppSettings.shared.providers
            for (providerID, models) in updates {
                guard let index = self.providers.firstIndex(where: { $0.id == providerID }) else { continue }
                var provider = self.providers[index]
                provider.modelPresets = ModelCatalog.merged(models, with: provider)
                if provider.model.isEmpty {
                    provider.model = provider.modelPresets.first ?? ""
                }
                self.providers[index] = provider
                AppSettings.shared.upsert(provider)
            }

            self.rebuildSections()
            self.tableView.reloadData()
        }
    }

    // MARK: - Действия

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }

    @objc private func pullToRefresh() {
        loadAll(force: true)
    }

    // MARK: - UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].entries.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 62
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 34
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        container.backgroundColor = Theme.surface

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = sections[section].title.uppercased()
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Theme.accent
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -28)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: UnifiedModelCell.reuseIdentifier) as? UnifiedModelCell
            ?? UnifiedModelCell(style: .default, reuseIdentifier: UnifiedModelCell.reuseIdentifier)

        let entry = sections[indexPath.section].entries[indexPath.row]
        if entry.isCustom {
            cell.configure(title: "Своя модель…",
                           provider: entry.provider.name,
                           isFree: false,
                           isSelected: false)
            return cell
        }

        let isSelected = entry.provider.id == selectedProviderID && entry.model == selectedModel
        let title = ChatModelPickerViewController.displayName(for: entry.model)
        let free = ChatModelPickerViewController.isFree(entry.model)

        cell.configure(title: title,
                       provider: entry.provider.name,
                       isFree: free,
                       isSelected: isSelected)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = sections[indexPath.section].entries[indexPath.row]

        if entry.isCustom {
            promptCustomModel(provider: entry.provider)
            return
        }

        AppSettings.shared.addRecentModel(entry.model, providerID: entry.provider.id)
        onSelect(entry.provider, entry.model)
        navigationController?.popViewController(animated: true)
    }

    private func promptCustomModel(provider: ProviderConfig) {
        let alert = UIAlertController(title: "Своя модель",
                                      message: provider.name,
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "например, gpt-4o-mini"
            field.text = provider.model
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Выбрать", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let value = (alert?.textFields?.first?.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }

            var updated = provider
            if !updated.modelPresets.contains(value) {
                updated.modelPresets.insert(value, at: 0)
            }
            updated.model = value
            AppSettings.shared.upsert(updated)
            AppSettings.shared.addRecentModel(value, providerID: provider.id)
            self.onSelect(updated, value)
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true, completion: nil)
    }

    // MARK: - UISearchBarDelegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        rebuildSections()
        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchBar.resignFirstResponder()
    }

    // MARK: - Отображение моделей

    static func displayName(for model: String) -> String {
        var value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasSuffix(":free") {
            value = String(value.dropLast(":free".count))
        }
        if let slash = value.lastIndex(of: "/") {
            value = String(value[value.index(after: slash)...])
        }
        value = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        let words = value.split(separator: " ").map { word -> String in
            switch word.lowercased() {
            case "gpt": return "GPT"
            case "ai": return "AI"
            case "llm": return "LLM"
            case "api": return "API"
            case "hd": return "HD"
            case "vl": return "VL"
            default:
                if word.first?.isNumber == true { return String(word) }
                return word.prefix(1).uppercased() + String(word.dropFirst())
            }
        }
        let result = words.joined(separator: " ")
        return result.isEmpty ? model : result
    }

    static func isFree(_ model: String) -> Bool {
        let lower = model.lowercased()
        return lower.contains(":free") || lower.contains("-free") || lower.hasSuffix("free")
    }
}

/// Строка единого списка: название модели, бейдж «Бесплатно»,
/// имя провайдера и отметка выбора.
final class UnifiedModelCell: CardCell {

    static let reuseIdentifier = "UnifiedModelCell"

    private let titleLabel = UILabel()
    private let providerLabel = UILabel()
    private let freeBadge = FreeBadgeLabel()
    private let checkLabel = UILabel()
    private let rightStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cardView.addSubview(titleLabel)

        providerLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        providerLabel.textColor = Theme.secondaryText
        providerLabel.textAlignment = .right
        providerLabel.numberOfLines = 1
        providerLabel.lineBreakMode = .byTruncatingTail
        providerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        providerLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 90).isActive = true

        freeBadge.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        freeBadge.textColor = Theme.success
        freeBadge.backgroundColor = Theme.successContainer

        checkLabel.text = "✓"
        checkLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        checkLabel.textColor = Theme.accent
        checkLabel.textAlignment = .center
        checkLabel.widthAnchor.constraint(equalToConstant: 18).isActive = true

        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.axis = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .center
        rightStack.addArrangedSubview(freeBadge)
        rightStack.addArrangedSubview(providerLabel)
        rightStack.addArrangedSubview(checkLabel)
        cardView.addSubview(rightStack)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),

            rightStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            rightStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            rightStack.leadingAnchor.constraint(greaterThanOrEqualTo: cardView.leadingAnchor, constant: 60)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, provider: String, isFree: Bool, isSelected: Bool) {
        titleLabel.text = title
        titleLabel.textColor = isSelected ? Theme.accent : Theme.primaryText
        providerLabel.text = provider
        freeBadge.text = "Бесплатно"
        freeBadge.isHidden = !isFree
        checkLabel.isHidden = !isSelected
    }
}

/// Маленький бейдж с внутренними отступами («Бесплатно»).
final class FreeBadgeLabel: UILabel {

    private let insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 8
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.cornerRadius = 8
        layer.masksToBounds = true
    }

    override func drawText(in rect: CGRect) {
        let insetRect = CGRect(x: rect.minX + insets.left,
                               y: rect.minY + insets.top,
                               width: max(0, rect.width - insets.left - insets.right),
                               height: max(0, rect.height - insets.top - insets.bottom))
        super.drawText(in: insetRect)
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}
