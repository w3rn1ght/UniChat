import UIKit
import QuickLook

final class MessageCell: UITableViewCell {

    static let reuseIdentifier = "MessageCell"

    var onAttachmentTap: ((ChatAttachment) -> Void)?

    private var displayedAttachments: [ChatAttachment] = []

    private let bubbleView = UIView()
    private let stackView = UIStackView()
    private let headerLabel = UILabel()
    private let attachmentsStack = UIStackView()
    private let messageLabel = UILabel()

    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = Theme.cornerLarge
        if #available(iOS 13.0, *) {
            bubbleView.layer.cornerCurve = .continuous
        }
        bubbleView.layer.masksToBounds = true
        contentView.addSubview(bubbleView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 3
        bubbleView.addSubview(stackView)

        headerLabel.font = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        headerLabel.textColor = Theme.secondaryText
        headerLabel.alpha = 0.9
        headerLabel.numberOfLines = 1
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        messageLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        attachmentsStack.axis = .vertical
        attachmentsStack.spacing = 6
        attachmentsStack.alignment = .leading
        attachmentsStack.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(headerLabel)
        stackView.addArrangedSubview(attachmentsStack)
        stackView.addArrangedSubview(messageLabel)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.88),

            stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 11),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -15),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -11)
        ])
    }

    func configure(with message: ChatMessage, providerTitle: String?, streaming: Bool) {
        let isUser = message.role == .user

        leadingConstraint.isActive = !isUser
        trailingConstraint.isActive = isUser

        if isUser {
            bubbleView.backgroundColor = Theme.outgoingBubble
        } else if message.isError {
            bubbleView.backgroundColor = Theme.dangerContainer
        } else {
            bubbleView.backgroundColor = Theme.incomingBubble
        }

        bubbleView.layer.borderWidth = 0
        if isUser {
            bubbleView.layer.maskedCorners = [.layerMinXMinYCorner,
                                             .layerMaxXMinYCorner,
                                             .layerMinXMaxYCorner]
        } else {
            bubbleView.layer.maskedCorners = [.layerMinXMinYCorner,
                                             .layerMaxXMinYCorner,
                                             .layerMaxXMaxYCorner]
        }

        if isUser {
            headerLabel.isHidden = true
        } else {
            headerLabel.isHidden = false
            if message.isError {
                headerLabel.text = "Ошибка"
                headerLabel.textColor = Theme.danger
            } else {
                headerLabel.text = providerTitle ?? "Ассистент"
                headerLabel.textColor = Theme.secondaryText
            }
        }

        let textColor: UIColor
        if isUser {
            textColor = Theme.onOutgoingBubble
        } else if message.isError {
            textColor = Theme.danger
        } else {
            textColor = Theme.primaryText
        }

        configureAttachments(message.attachments, isUser: isUser)

        var displayText = message.text
        if streaming {
            displayText = displayText.isEmpty ? "▍" : displayText + " ▍"
        }
        messageLabel.isHidden = displayText.isEmpty
        messageLabel.attributedText = Markdown.render(displayText, color: textColor)
        messageLabel.accessibilityLabel = displayText
    }

    private func configureAttachments(_ attachments: [ChatAttachment], isUser: Bool) {
        displayedAttachments = attachments
        for view in attachmentsStack.arrangedSubviews {
            attachmentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        attachmentsStack.isHidden = attachments.isEmpty

        for (index, attachment) in attachments.enumerated() {
            if attachment.isImage, let image = UIImage(data: attachment.data) {
                let imageView = UIImageView(image: image)
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.layer.cornerRadius = 10
                imageView.isUserInteractionEnabled = true
                imageView.tag = index
                imageView.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                      action: #selector(attachmentTapped(_:))))
                imageView.heightAnchor.constraint(equalToConstant: 150).isActive = true
                imageView.widthAnchor.constraint(equalToConstant: 220).isActive = true
                attachmentsStack.addArrangedSubview(imageView)
            } else {
                let container = UIView()
                container.translatesAutoresizingMaskIntoConstraints = false
                container.backgroundColor = isUser
                    ? UIColor(white: 1.0, alpha: 0.16)
                    : Theme.surfaceContainer
                container.layer.cornerRadius = 10
                container.isUserInteractionEnabled = true
                container.tag = index
                container.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                      action: #selector(attachmentTapped(_:))))

                let label = UILabel()
                label.translatesAutoresizingMaskIntoConstraints = false
                label.numberOfLines = 2
                label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
                label.textColor = isUser ? Theme.onOutgoingBubble : Theme.primaryText
                label.text = "📄 \(attachment.name)\n\(attachment.sizeText)"
                container.addSubview(label)

                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
                    label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
                    label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                    label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
                    container.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                    container.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
                ])
                attachmentsStack.addArrangedSubview(container)
            }
        }
    }

    func updateStreamingText(_ text: String, providerTitle: String?, isError: Bool) {
        let displayText = text.isEmpty ? "▍" : text + " ▍"
        messageLabel.attributedText = Markdown.render(displayText,
                                                   color: isError ? Theme.danger : Theme.primaryText)
        headerLabel.text = isError ? "Ошибка" : (providerTitle ?? "Ассистент")
        headerLabel.textColor = isError ? Theme.danger : Theme.secondaryText
    }

    @objc private func attachmentTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag,
              displayedAttachments.indices.contains(index) else { return }
        onAttachmentTap?(displayedAttachments[index])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        displayedAttachments = []
        headerLabel.isHidden = false
        headerLabel.text = nil
        messageLabel.attributedText = nil
        messageLabel.isHidden = false
        for view in attachmentsStack.arrangedSubviews {
            attachmentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        attachmentsStack.isHidden = true
    }
}

/// Просмотр изображения, PDF, текста и других файлов через QuickLook.
final class AttachmentPreviewController: QLPreviewController, QLPreviewControllerDataSource {

    private let fileURL: URL

    init(attachment: ChatAttachment) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UniChatPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        let originalName = attachment.name.isEmpty ? "file" : attachment.name
        let ext = (originalName as NSString).pathExtension
        let fileName = UUID().uuidString + (ext.isEmpty ? "" : "." + ext.lowercased())
        let url = directory.appendingPathComponent(fileName)
        try? attachment.data.write(to: url, options: .atomic)
        self.fileURL = url

        super.init(nibName: nil, bundle: nil)
        dataSource = self
        title = attachment.name
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController,
                           previewItemAt index: Int) -> QLPreviewItem {
        return fileURL as NSURL
    }
}
