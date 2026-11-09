import UIKit

protocol ComposerViewDelegate: AnyObject {
    func composer(_ composer: ComposerView, didSend text: String, attachments: [ChatAttachment])
    func composerDidRequestStop(_ composer: ComposerView)
    func composerDidRequestAttachment(_ composer: ComposerView)
}

final class ComposerView: UIView, UITextViewDelegate {

    weak var delegate: ComposerViewDelegate?

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private let attachmentsScroll = UIScrollView()
    private let attachmentsStack = UIStackView()
    private var textViewHeight: NSLayoutConstraint!
    private var previewHeight: NSLayoutConstraint!

    private(set) var attachments: [ChatAttachment] = []

    private let minHeight: CGFloat = 44
    private let maxHeight: CGFloat = 120

    var isStreaming: Bool = false {
        didSet { updateSendButton() }
    }

    var text: String {
        return textView.text ?? ""
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = Theme.surface

        attachmentsScroll.translatesAutoresizingMaskIntoConstraints = false
        attachmentsScroll.showsHorizontalScrollIndicator = false
        attachmentsScroll.alwaysBounceHorizontal = true
        attachmentsScroll.isHidden = true
        addSubview(attachmentsScroll)

        attachmentsStack.translatesAutoresizingMaskIntoConstraints = false
        attachmentsStack.axis = .horizontal
        attachmentsStack.spacing = 8
        attachmentsStack.alignment = .fill
        attachmentsScroll.addSubview(attachmentsStack)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.font = Theme.bodyFont
        textView.isScrollEnabled = false
        textView.backgroundColor = Theme.surfaceContainer
        textView.textColor = Theme.primaryText
        textView.layer.cornerRadius = 24
        if #available(iOS 13.0, *) {
            textView.layer.cornerCurve = .continuous
        }
        textView.layer.borderWidth = 0
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 15, bottom: 11, right: 15)
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardAppearance = Theme.isDark ? .dark : .light
        textView.returnKeyType = .default
        addSubview(textView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "Сообщение…"
        placeholderLabel.font = Theme.bodyFont
        placeholderLabel.textColor = Theme.secondaryText
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        attachButton.translatesAutoresizingMaskIntoConstraints = false
        attachButton.setTitle("+", for: .normal)
        attachButton.setTitleColor(Theme.onPrimaryContainer, for: .normal)
        attachButton.titleLabel?.font = UIFont.systemFont(ofSize: 26, weight: .regular)
        attachButton.backgroundColor = Theme.primaryContainer
        attachButton.layer.cornerRadius = 20
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        addSubview(attachButton)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setTitle("↑", for: .normal)
        sendButton.setTitleColor(Theme.onAccent, for: .normal)
        sendButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        sendButton.backgroundColor = Theme.accent
        sendButton.layer.cornerRadius = 22
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        addSubview(sendButton)

        textViewHeight = textView.heightAnchor.constraint(equalToConstant: minHeight)
        previewHeight = attachmentsScroll.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            attachmentsScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            attachmentsScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            attachmentsScroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            previewHeight,

            attachmentsStack.leadingAnchor.constraint(equalTo: attachmentsScroll.contentLayoutGuide.leadingAnchor),
            attachmentsStack.trailingAnchor.constraint(equalTo: attachmentsScroll.contentLayoutGuide.trailingAnchor),
            attachmentsStack.topAnchor.constraint(equalTo: attachmentsScroll.contentLayoutGuide.topAnchor),
            attachmentsStack.bottomAnchor.constraint(equalTo: attachmentsScroll.contentLayoutGuide.bottomAnchor),
            attachmentsStack.heightAnchor.constraint(equalToConstant: 56),

            textView.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 8),
            textView.topAnchor.constraint(equalTo: attachmentsScroll.bottomAnchor, constant: 6),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textViewHeight,

            attachButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            attachButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 40),
            attachButton.heightAnchor.constraint(equalToConstant: 40),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 11),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -12),

            sendButton.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        updateSendButton()
    }

    func clear() {
        textView.text = ""
        attachments.removeAll()
        rebuildPreviews()
        textViewDidChange(textView)
    }

    func addAttachment(_ attachment: ChatAttachment) {
        attachments.append(attachment)
        rebuildPreviews()
    }

    private func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
        rebuildPreviews()
    }

    private func rebuildPreviews() {
        for view in attachmentsStack.arrangedSubviews {
            attachmentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for attachment in attachments {
            let chip = AttachmentChipView(attachment: attachment)
            chip.onRemove = { [weak self] id in
                self?.removeAttachment(id: id)
            }
            attachmentsStack.addArrangedSubview(chip)
        }

        attachmentsScroll.isHidden = attachments.isEmpty
        previewHeight.constant = attachments.isEmpty ? 0 : 62
        updateSendButton()

        UIView.animate(withDuration: 0.15) {
            self.superview?.layoutIfNeeded()
        }
    }

    func focus() {
        textView.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func attachTapped() {
        if isStreaming { return }
        delegate?.composerDidRequestAttachment(self)
    }

    @objc private func sendTapped() {
        if isStreaming {
            delegate?.composerDidRequestStop(self)
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        delegate?.composer(self, didSend: trimmed, attachments: attachments)
    }

    private func updateSendButton() {
        if isStreaming {
            sendButton.setTitle("■", for: .normal)
            sendButton.setTitleColor(.white, for: .normal)
            sendButton.backgroundColor = Theme.danger
            sendButton.isEnabled = true
            sendButton.alpha = 1.0
        } else {
            sendButton.setTitle("↑", for: .normal)
            let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty
            sendButton.backgroundColor = hasContent ? Theme.accent : Theme.surfaceContainerHigh
            sendButton.setTitleColor(hasContent ? Theme.onAccent : Theme.secondaryText, for: .normal)
            sendButton.isEnabled = hasContent
            sendButton.alpha = 1.0
        }
    }

    private func updateHeight() {
        let width = textView.bounds.width
        guard width > 0 else { return }

        let fitting = textView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let target = min(max(minHeight, ceil(fitting.height)), maxHeight)
        let shouldScroll = fitting.height > maxHeight

        if textView.isScrollEnabled != shouldScroll {
            textView.isScrollEnabled = shouldScroll
        }
        if abs(textViewHeight.constant - target) > 0.5 {
            textViewHeight.constant = target
            UIView.animate(withDuration: 0.12) {
                self.superview?.layoutIfNeeded()
            }
        }
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
        updateHeight()
        updateSendButton()
    }
}

/// Небольшая карточка вложения над полем ввода: иконка, имя и «×».
final class AttachmentChipView: UIView {

    var onRemove: ((UUID) -> Void)?

    private let attachment: ChatAttachment
    private let iconLabel = UILabel()
    private let nameLabel = UILabel()
    private let removeButton = UIButton(type: .system)

    init(attachment: ChatAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Theme.surfaceContainerHigh
        layer.cornerRadius = 12
        if #available(iOS 13.0, *) {
            layer.cornerCurve = .continuous
        }
        clipsToBounds = true

        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.text = attachment.isImage ? "🖼" : "📄"
        iconLabel.font = UIFont.systemFont(ofSize: 20)
        iconLabel.textAlignment = .center
        addSubview(iconLabel)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = attachment.name
        nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = Theme.primaryText
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setTitle("×", for: .normal)
        removeButton.setTitleColor(Theme.secondaryText, for: .normal)
        removeButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            widthAnchor.constraint(lessThanOrEqualToConstant: 210),

            iconLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 26),

            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 7),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            removeButton.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 26),
            removeButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func removeTapped() {
        onRemove?(attachment.id)
    }
}
