import UIKit

/// Выбор любой доступной модели провайдера с поиском и автоподгрузкой списка.
final class ModelPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    UISearchBarDelegate {

    private var provider: ProviderConfig
    private let selectedModel: String
    private let onSelect: (String) -> Void

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let footerLabel = UILabel()

    private var models: [String] = []
    private var filtered: [String] = []
    private var isLoading = false
    private var loadError: String?

    private let actionSection = 0
    private let modelsSection = 1

    init(provider: ProviderConfig,
         selectedModel: String,
         onSelect: @escaping (String) -> Void) {
        self.provider = provider
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

        models = provider.modelPresets
        if !models.contains(provider.model) && !provider.model.isEmpty {
            models.insert(provider.model, at: 0)
        }
        if !models.contains(selectedModel) && !selectedModel.isEmpty {
            models.insert(selectedModel, at: 0)
        }
        filtered = models

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh,
                                                            target: self,
                                                            action: #selector(refreshTapped))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.surface
        tableView.separatorStyle = .none
        tableView.rowHeight = 70
        tableView.estimatedRowHeight = 70
        tableView.keyboardDismissMode = .onDrag
        tableView.sectionHeaderHeight = 34
        tableView.sectionFooterHeight = 0
        view.addSubview(tableView)

        setupHeader()
        setupFooter()

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        navigationItem.largeTitleDisplayMode = .never

        // Если список ещё не загружали, подтягиваем его автоматически.
        if ModelCatalog.supportsDiscovery(provider.kind),
           provider.modelPresets.count <= 6,
           (!provider.trimmedAPIKey.isEmpty || provider.kind == .openAICompatible) {
            refreshModels(silent: true)
        }
    }

    private func setupHeader() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 60))
        container.backgroundColor = Theme.surface

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = "Найти модель"
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
        footerLabel.font = UIFont.systemFont(ofSize: 12)
        footerLabel.textColor = Theme.secondaryText
        footerLabel.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 56)
        updateFooter()
        tableView.tableFooterView = footerLabel
    }

    private func updateFooter() {
        if isLoading {
            footerLabel.text = "Загружаем список моделей…"
        } else if let error = loadError {
            footerLabel.text = error
            footerLabel.textColor = Theme.danger
        } else {
            footerLabel.text = "Найдено моделей: \(models.count). Список можно обновить кнопкой ↻."
            footerLabel.textColor = Theme.secondaryText
        }
    }

    // MARK: - Действия

    @objc private func refreshTapped() {
        refreshModels(silent: false)
    }

    private func refreshModels(silent: Bool) {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        navigationItem.rightBarButtonItem?.isEnabled = false
        tableView.reloadData()
        updateFooter()

        ModelCatalog.fetch(for: provider) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.navigationItem.rightBarButtonItem?.isEnabled = true

            switch result {
            case .success(let fetched):
                var merged = fetched
                // Текущую модель не теряем, даже если шлюз её скрыл.
                if !self.provider.model.isEmpty && !merged.contains(self.provider.model) {
                    merged.insert(self.provider.model, at: 0)
                }
                if !self.selectedModel.isEmpty && !merged.contains(self.selectedModel) {
                    merged.insert(self.selectedModel, at: 0)
                }

                self.provider.modelPresets = merged
                AppSettings.shared.upsert(self.provider)
                self.models = merged
                self.applyFilter(self.searchBar.text ?? "")
                self.tableView.reloadData()
                self.updateFooter()

                if !silent && merged.isEmpty {
                    self.loadError = "Провайдер не вернул ни одной модели."
                    self.updateFooter()
                }

            case .failure(let error):
                self.loadError = error.localizedDescription
                self.tableView.reloadData()
                self.updateFooter()
                if !silent {
                    let alert = UIAlertController(title: "Не удалось загрузить модели",
                                                  message: error.localizedDescription,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }
    }

    private func applyFilter(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            filtered = models
        } else {
            filtered = models.filter { $0.lowercased().contains(trimmed) }
        }
    }

    // MARK: - UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == actionSection ? 1 : filtered.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == modelsSection {
            return "МОДЕЛИ · \(filtered.count)"
        }
        return nil
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = self.tableView(tableView, titleForHeaderInSection: section) else {
            return nil
        }
        let container = UIView()
        container.backgroundColor = Theme.surface

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.accent
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == modelsSection ? 34 : 8
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == actionSection {
            let cell = MaterialRowCell(style: .default, reuseIdentifier: nil)
            cell.configure(badgeText: "+",
                           badgeBackground: Theme.secondaryContainer,
                           badgeForeground: Theme.onSecondaryContainer,
                           badgeFontSize: 20,
                           title: "Своя модель",
                           subtitle: "Ввести название вручную",
                           accessory: nil,
                           showsChevron: true)
            return cell
        }

        let cell = ModelChoiceCell(style: .default, reuseIdentifier: nil)
        let model = filtered[indexPath.row]
        cell.configure(model: model,
                       selected: model == selectedModel,
                       isFree: model.lowercased().hasSuffix(":free"))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == actionSection {
            promptCustomModel()
            return
        }

        let model = filtered[indexPath.row]
        onSelect(model)
        navigationController?.popViewController(animated: true)
    }

    private func promptCustomModel() {
        let alert = UIAlertController(title: "Своя модель",
                                      message: "Введите идентификатор модели, например gemini-2.5-flash",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.text = self.selectedModel
            field.placeholder = "model-id"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Выбрать", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let value = alert.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return }
            if !self.provider.modelPresets.contains(value) {
                self.provider.modelPresets.insert(value, at: 0)
                AppSettings.shared.upsert(self.provider)
            }
            self.onSelect(value)
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true, completion: nil)
    }

    // MARK: - UISearchBarDelegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter(searchText)
        tableView.reloadSections(IndexSet(integer: modelsSection), with: .none)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

/// Строка списка моделей с отметкой выбора.
final class ModelChoiceCell: CardCell {

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checkView = UIView()
    private let checkLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        cardView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = Theme.secondaryText
        cardView.addSubview(subtitleLabel)

        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.layer.masksToBounds = true
        checkView.layer.cornerRadius = 12
        cardView.addSubview(checkView)

        checkLabel.translatesAutoresizingMaskIntoConstraints = false
        checkLabel.text = "✓"
        checkLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        checkLabel.textAlignment = .center
        checkView.addSubview(checkLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: checkView.leadingAnchor, constant: -12),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.trailingAnchor.constraint(equalTo: checkView.leadingAnchor, constant: -12),

            checkView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            checkView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 24),
            checkView.heightAnchor.constraint(equalToConstant: 24),

            checkLabel.centerXAnchor.constraint(equalTo: checkView.centerXAnchor),
            checkLabel.centerYAnchor.constraint(equalTo: checkView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(model: String, selected: Bool, isFree: Bool) {
        titleLabel.text = model
        subtitleLabel.text = isFree ? "Бесплатная модель" : "Нажмите, чтобы выбрать"
        if selected {
            checkView.backgroundColor = Theme.accent
            checkView.layer.borderWidth = 0
            checkLabel.textColor = .white
            checkLabel.isHidden = false
            titleLabel.textColor = Theme.accent
        } else {
            checkView.backgroundColor = .clear
            checkView.layer.borderWidth = 1.5
            checkView.layer.borderColor = Theme.separator.cgColor
            checkLabel.isHidden = true
            titleLabel.textColor = Theme.primaryText
        }
    }
}
