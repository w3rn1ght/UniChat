import UIKit

final class ChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
    ComposerViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
    UIDocumentPickerDelegate {

    private var conversation: Conversation
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let composer = ComposerView()
    private let contextBar = UIView()
    private let contextButton = UIButton(type: .system)
    private let emptyLabel = UILabel()
    private let emptyBadge = CircleBadgeView()

    private var composerBottomConstraint: NSLayoutConstraint!
    private var activeSession: CancellableTask?
    private var isStreaming = false
    private var streamingMessageID: UUID?
    private var streamingText = ""
    private var pendingStreamingRefresh = false
    private var wasCancelled = false
    private var autoScroll = true

    init(conversation: Conversation) {
        self.conversation = conversation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.surface
        title = conversation.title
        navigationItem.largeTitleDisplayMode = .never

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "•••",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(showChatMenu))

        ensureProvider()
        setupContextBar()
        setupTableView()
        setupComposer()
        setupEmptyLabel()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        tableView.addGestureRecognizer(longPress)

        updateContextBar()
        updateEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateContextBar()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent else { return }
        if isStreaming {
            wasCancelled = true
            activeSession?.cancel()
        }
        if conversation.messages.isEmpty {
            ConversationStore.shared.delete(id: conversation.id)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
    }

    // MARK: - UI

    private func setupContextBar() {
        contextBar.translatesAutoresizingMaskIntoConstraints = false
        contextBar.backgroundColor = Theme.surface
        view.addSubview(contextBar)

        contextButton.translatesAutoresizingMaskIntoConstraints = false
        contextButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        contextButton.titleLabel?.lineBreakMode = .byTruncatingMiddle
        contextButton.setTitleColor(Theme.onPrimaryContainer, for: .normal)
        contextButton.backgroundColor = Theme.primaryContainer
        contextButton.layer.cornerRadius = 17
        contextButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        contextButton.addTarget(self, action: #selector(openModelPicker), for: .touchUpInside)
        contextBar.addSubview(contextButton)

        NSLayoutConstraint.activate([
            contextBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contextBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contextBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contextBar.heightAnchor.constraint(equalToConstant: 48),

            contextButton.centerYAnchor.constraint(equalTo: contextBar.centerYAnchor),
            contextButton.centerXAnchor.constraint(equalTo: contextBar.centerXAnchor),
            contextButton.leadingAnchor.constraint(greaterThanOrEqualTo: contextBar.leadingAnchor, constant: 12),
            contextButton.trailingAnchor.constraint(lessThanOrEqualTo: contextBar.trailingAnchor, constant: -12)
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseIdentifier)
        tableView.backgroundColor = Theme.surface
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 90
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        tableView.keyboardDismissMode = .interactive
        view.addSubview(tableView)
    }

    private func setupComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.delegate = self
        view.addSubview(composer)

        composerBottomConstraint = composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottomConstraint,

            tableView.topAnchor.constraint(equalTo: contextBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: composer.topAnchor)
        ])
    }

    private func setupEmptyLabel() {
        emptyBadge.configure(text: "✦",
                             background: Theme.primaryContainer,
                             foreground: Theme.onPrimaryContainer,
                             fontSize: 30)
        view.addSubview(emptyBadge)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Спросите что угодно\nПровайдер и модель — на панели сверху."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.textColor = Theme.secondaryText
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyBadge.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyBadge.centerYAnchor.constraint(equalTo: tableView.centerYAnchor, constant: -52),
            emptyBadge.widthAnchor.constraint(equalToConstant: 72),
            emptyBadge.heightAnchor.constraint(equalToConstant: 72),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: emptyBadge.bottomAnchor, constant: 18),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30)
        ])
    }

    private func updateEmptyState() {
        let isEmpty = conversation.messages.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyBadge.isHidden = !isEmpty
    }

    private var currentProvider: ProviderConfig? {
        if let provider = AppSettings.shared.provider(id: conversation.providerID) {
            return provider
        }
        return AppSettings.shared.firstProvider()
    }

    private func ensureProvider() {
        if AppSettings.shared.provider(id: conversation.providerID) == nil {
            if let first = AppSettings.shared.firstProvider() {
                conversation.providerID = first.id
                if (conversation.model ?? "").isEmpty {
                    conversation.model = first.model
                }
            }
        }
        if (conversation.model ?? "").isEmpty, let provider = currentProvider {
            conversation.model = provider.model
        }
    }

    private func updateContextBar() {
        let provider = currentProvider
        let model = conversation.model ?? provider?.model ?? "—"
        let name = provider?.name ?? "Провайдер"
        contextButton.setTitle("\(name) · \(model)  ▾", for: .normal)
    }

    // MARK: - UITableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversation.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseIdentifier,
                                                 for: indexPath) as! MessageCell
        let message = conversation.messages[indexPath.row]
        let streaming = isStreaming && message.id == streamingMessageID
        let provider = currentProvider
        let model = message.modelName ?? conversation.model ?? provider?.model ?? ""
        let providerTitle = "\(provider?.name ?? "Ассистент") · \(model)"
        cell.configure(with: message, providerTitle: providerTitle, streaming: streaming)
        return cell
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        autoScroll = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
        if visibleBottom >= scrollView.contentSize.height - 100 {
            autoScroll = true
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard autoScroll, !conversation.messages.isEmpty else { return }
        tableView.layoutIfNeeded()
        let indexPath = IndexPath(row: conversation.messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    // MARK: - Composer

    func composer(_ composer: ComposerView, didSend text: String, attachments: [ChatAttachment]) {
        guard !isStreaming else { return }
        guard !text.isEmpty || !attachments.isEmpty else { return }

        guard let provider = currentProvider else {
            presentSimpleAlert(title: "Нет провайдера", message: "Добавьте провайдера в настройках.")
            return
        }
        guard provider.isReady else {
            presentNotReadyAlert(provider: provider)
            return
        }

        if provider.kind.isAccount && !attachments.isEmpty {
            presentSimpleAlert(
                title: "Вложения недоступны",
                message: "В режиме входа в аккаунт нельзя отправлять фото и файлы. Выберите API-провайдера (OpenRouter, AnyModel или Gemini API)."
            )
            return
        }

        conversation.providerID = provider.id
        if (conversation.model ?? "").isEmpty {
            conversation.model = provider.model
        }

        let message = ChatMessage(role: .user, text: text, attachments: attachments)
        conversation.messages.append(message)

        if conversation.title == "Новый чат" || conversation.title.isEmpty {
            let titleSource = text.isEmpty ? (attachments.first?.name ?? "Вложение") : text
            conversation.title = ChatViewController.makeTitle(from: titleSource)
            navigationItem.title = conversation.title
        }

        conversation.updatedAt = Date()
        ConversationStore.shared.update(conversation)
        composer.clear()

        autoScroll = true
        tableView.reloadData()
        updateEmptyState()
        scrollToBottom(animated: true)

        beginStreaming(provider: provider)
    }

    func composerDidRequestStop(_ composer: ComposerView) {
        guard isStreaming else { return }
        wasCancelled = true
        activeSession?.cancel()
    }

    func composerDidRequestAttachment(_ composer: ComposerView) {
        guard !isStreaming else { return }
        view.endEditing(true)

        let alert = UIAlertController(title: "Прикрепить", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Фото из галереи", style: .default) { _ in
            self.openPhotoLibrary()
        })
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Сделать фото", style: .default) { _ in
                self.openCamera()
            })
        }
        alert.addAction(UIAlertAction(title: "Файл", style: .default) { _ in
            self.openDocumentPicker()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))

        alert.popoverPresentationController?.sourceView = composer
        alert.popoverPresentationController?.sourceRect = composer.bounds
        present(alert, animated: true, completion: nil)
    }

    private func beginStreaming(provider: ProviderConfig) {
        let model = (conversation.model ?? provider.model).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            presentSimpleAlert(title: "Не задана модель", message: "Укажите модель в настройках провайдера.")
            return
        }

        let assistant = ChatMessage(role: .assistant, text: "", modelName: model)
        conversation.messages.append(assistant)

        streamingMessageID = assistant.id
        streamingText = ""
        isStreaming = true
        wasCancelled = false
        composer.isStreaming = true
        autoScroll = true

        tableView.reloadData()
        updateEmptyState()
        scrollToBottom(animated: true)

        let request = ChatRequest(model: model,
                                  messages: conversation.messages,
                                  systemPrompt: provider.systemPrompt)
        let runner = ProviderFactory.make(for: provider)

        activeSession = runner.streamChat(request, onDelta: { [weak self] delta in
            self?.append(delta: delta)
        }, onFinish: { [weak self] error in
            self?.finishStreaming(error: error)
        })
    }

    private func append(delta: String) {
        if delta.hasPrefix("\u{0}") {
            streamingText = String(delta.dropFirst())
        } else {
            streamingText += delta
        }

        guard let id = streamingMessageID,
              let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[index].text = streamingText
        scheduleStreamingRefresh()
    }

    private func scheduleStreamingRefresh() {
        guard !pendingStreamingRefresh else { return }
        pendingStreamingRefresh = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            self.pendingStreamingRefresh = false

            guard self.isStreaming,
                  let id = self.streamingMessageID,
                  let index = self.conversation.messages.firstIndex(where: { $0.id == id }) else { return }

            UIView.performWithoutAnimation {
                self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
            self.scrollToBottom(animated: false)
        }
    }

    private func finishStreaming(error: Error?) {
        isStreaming = false
        composer.isStreaming = false
        activeSession = nil

        guard let id = streamingMessageID,
              let index = conversation.messages.firstIndex(where: { $0.id == id }) else {
            streamingMessageID = nil
            wasCancelled = false
            return
        }

        let cancelled = wasCancelled
        let trimmedText = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)

        if cancelled {
            if trimmedText.isEmpty {
                conversation.messages.remove(at: index)
            } else {
                conversation.messages[index].text = streamingText
            }
        } else if let error = error {
            if trimmedText.isEmpty {
                conversation.messages[index].text = error.localizedDescription
                conversation.messages[index].isError = true
            } else {
                conversation.messages[index].text = streamingText + "\n\n⚠️ " + error.localizedDescription
            }
        } else if trimmedText.isEmpty {
            conversation.messages[index].text = "Пустой ответ от провайдера."
            conversation.messages[index].isError = true
        } else {
            conversation.messages[index].text = streamingText
        }

        streamingMessageID = nil
        streamingText = ""
        wasCancelled = false

        conversation.updatedAt = Date()
        ConversationStore.shared.update(conversation)
        ConversationStore.shared.save()

        tableView.reloadData()
        updateEmptyState()
        scrollToBottom(animated: true)
    }

    // MARK: - Вложения

    private func openPhotoLibrary() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentSimpleAlert(title: "Камера недоступна", message: "На этом устройстве нет камеры.")
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }

    private func openDocumentPicker() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true, completion: nil)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        picker.dismiss(animated: true) { [weak self] in
            guard let self = self, let picked = image else { return }
            guard let attachment = self.makeImageAttachment(from: picked, name: "photo.jpg") else {
                self.presentSimpleAlert(title: "Не удалось добавить фото",
                                        message: "Попробуйте выбрать другое изображение.")
                return
            }
            self.composer.addAttachment(attachment)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        controller.dismiss(animated: true) { [weak self] in
            self?.importDocument(at: url)
        }
    }

    private func importDocument(at url: URL) {
        let name = url.lastPathComponent
        let sizeLimit = 12 * 1024 * 1024
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            presentSimpleAlert(title: "Не удалось прочитать файл", message: error.localizedDescription)
            return
        }

        guard data.count <= sizeLimit else {
            presentSimpleAlert(title: "Файл слишком большой",
                               message: "Максимальный размер вложения — 12 МБ.")
            return
        }

        let mime = ChatAttachment.mimeType(forFileName: name)
        let kind: ChatAttachmentKind = mime.hasPrefix("image/") ? .image : .file
        let attachment = ChatAttachment(name: name, mimeType: mime, kind: kind, data: data)
        composer.addAttachment(attachment)
    }

    private func makeImageAttachment(from image: UIImage, name: String) -> ChatAttachment? {
        let resized = resizedImage(image, maxDimension: 1600)
        var quality: CGFloat = 0.82
        var data = resized.jpegData(compressionQuality: quality)

        while let current = data, current.count > 6 * 1024 * 1024, quality > 0.3 {
            quality -= 0.15
            data = resized.jpegData(compressionQuality: quality)
        }

        guard let finalData = data else { return nil }
        return ChatAttachment(name: name,
                              mimeType: "image/jpeg",
                              kind: .image,
                              data: finalData)
    }

    private func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension, largest > 0 else { return image }

        let ratio = maxDimension / largest
        let target = CGSize(width: max(1, floor(size.width * ratio)),
                            height: max(1, floor(size.height * ratio)))

        UIGraphicsBeginImageContextWithOptions(target, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: target))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? image
    }

    // MARK: - Меню чата

    @objc private func showChatMenu() {
        view.endEditing(true)
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Переименовать", style: .default) { _ in
            self.promptRename()
        })
        alert.addAction(UIAlertAction(title: "Провайдеры и ключи", style: .default) { _ in
            self.navigationController?.pushViewController(SettingsViewController(), animated: true)
        })
        alert.addAction(UIAlertAction(title: "Очистить историю", style: .destructive) { _ in
            self.clearHistory()
        })
        alert.addAction(UIAlertAction(title: "Удалить чат", style: .destructive) { _ in
            self.confirmDeleteChat()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))

        alert.popoverPresentationController?.sourceView = navigationItem.rightBarButtonItem?.customView ?? view
        alert.popoverPresentationController?.sourceRect = view.bounds
        present(alert, animated: true, completion: nil)
    }

    private func promptRename() {
        let alert = UIAlertController(title: "Название чата", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = self.conversation.title
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
            let value = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                self.conversation.title = value
                self.title = value
                ConversationStore.shared.update(self.conversation)
            }
        })
        present(alert, animated: true, completion: nil)
    }

    private func clearHistory() {
        if isStreaming {
            wasCancelled = true
            activeSession?.cancel()
        }
        conversation.messages.removeAll()
        ConversationStore.shared.update(conversation)
        tableView.reloadData()
        updateEmptyState()
    }

    private func confirmDeleteChat() {
        let alert = UIAlertController(title: "Удалить чат?",
                                      message: "История сообщений будет удалена безвозвратно.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { _ in
            if self.isStreaming {
                self.wasCancelled = true
                self.activeSession?.cancel()
            }
            ConversationStore.shared.delete(id: self.conversation.id)
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Провайдер и модель

    @objc private func openModelPicker() {
        view.endEditing(true)
        let providers = AppSettings.shared.providers
        guard !providers.isEmpty else {
            presentSimpleAlert(title: "Нет провайдеров", message: "Добавьте провайдера в настройках.")
            return
        }

        let provider = currentProvider
        let selected = conversation.model ?? provider?.model ?? ""
        let picker = ChatModelPickerViewController(providers: providers,
                                                   selectedProviderID: provider?.id,
                                                   selectedModel: selected) { [weak self] provider, model in
            self?.applySelection(provider: provider, model: model)
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func applySelection(provider: ProviderConfig, model: String) {
        conversation.providerID = provider.id
        conversation.model = model
        AppSettings.shared.lastProviderID = provider.id
        AppSettings.shared.setLastModel(model, for: provider.id)
        AppSettings.shared.addRecentModel(model, providerID: provider.id)
        conversation.updatedAt = Date()
        ConversationStore.shared.update(conversation)
        updateContextBar()

        if !provider.isReady {
            // Ждём, пока список моделей закроется, иначе alert не покажется.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self = self,
                      self.view.window != nil,
                      self.presentedViewController == nil else { return }
                self.presentNotReadyAlert(provider: provider)
            }
        }
    }

    // MARK: - Сообщения

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isStreaming else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              indexPath.row < conversation.messages.count else { return }

        let message = conversation.messages[indexPath.row]
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Копировать", style: .default) { _ in
            UIPasteboard.general.string = message.text
        })

        if message.role == .assistant && indexPath.row == conversation.messages.count - 1 {
            alert.addAction(UIAlertAction(title: "Повторить ответ", style: .default) { _ in
                self.regenerateLast()
            })
        }

        alert.addAction(UIAlertAction(title: "Удалить сообщение", style: .destructive) { _ in
            guard indexPath.row < self.conversation.messages.count else { return }
            self.conversation.messages.remove(at: indexPath.row)
            ConversationStore.shared.update(self.conversation)
            self.tableView.reloadData()
            self.updateEmptyState()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))

        alert.popoverPresentationController?.sourceView = tableView
        alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        present(alert, animated: true, completion: nil)
    }

    private func regenerateLast() {
        guard !isStreaming, let provider = currentProvider else { return }
        guard provider.isReady else {
            presentNotReadyAlert(provider: provider)
            return
        }
        guard conversation.messages.contains(where: { $0.role == .user }) else { return }

        if let index = conversation.messages.lastIndex(where: { $0.role == .assistant }) {
            conversation.messages.remove(at: index)
        }
        tableView.reloadData()
        autoScroll = true
        beginStreaming(provider: provider)
    }

    // MARK: - Клавиатура

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        let inset = max(0, overlap - view.safeAreaInsets.bottom)

        composerBottomConstraint.constant = -inset

        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curve = UIView.AnimationCurve(rawValue: (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 7) ?? .easeInOut
        let options = UIView.AnimationOptions(rawValue: UInt(curve.rawValue) << 16)

        UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
            self.view.layoutIfNeeded()
        }, completion: { _ in
            if inset > 0 {
                self.scrollToBottom(animated: false)
            }
        })
    }

    // MARK: - Вспомогательное

    private func presentSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func presentNotReadyAlert(provider: ProviderConfig) {
        if provider.kind.isAccount {
            let message = "Для «\(provider.name)» нужно войти в аккаунт.\n\nВход выполняется на настоящем сайте провайдера: приложение не видит пароль."
            let alert = UIAlertController(title: "Нужен вход", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Позже", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Войти", style: .default) { _ in
                AppSettings.shared.upsert(provider)
                let controller = AccountLoginViewController(provider: provider) { [weak self] _ in
                    self?.updateContextBar()
                }
                self.navigationController?.pushViewController(controller, animated: true)
            })
            present(alert, animated: true, completion: nil)
            return
        }

        let message = "Для «\(provider.name)» не задан API-ключ.\n\nGemini: бесплатный ключ в Google AI Studio.\nDeepSeek, OpenRouter, AnyModel: ключ в личном кабинете.\n\nКлюч хранится только в Keychain на этом устройстве."
        let alert = UIAlertController(title: "Нужен API-ключ", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Позже", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Настройки", style: .default) { _ in
            self.navigationController?.pushViewController(SettingsViewController(), animated: true)
        })
        present(alert, animated: true, completion: nil)
    }

    private static func makeTitle(from text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flattened.count <= 40 { return flattened }
        return String(flattened.prefix(40)) + "…"
    }
}
