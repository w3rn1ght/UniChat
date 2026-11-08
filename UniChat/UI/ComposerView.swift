import UIKit

protocol ComposerViewDelegate: class {
    func composer(_ composer: ComposerView, didSend text: String)
    func composerDidRequestStop(_ composer: ComposerView)
}

final class ComposerView: UIView, UITextViewDelegate {

    weak var delegate: ComposerViewDelegate?

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private var textViewHeight: NSLayoutConstraint!

    private let minHeight: CGFloat = 38
    private let maxHeight: CGFloat = 110

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
        backgroundColor = Theme.card

        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = Theme.separator
        addSubview(hairline)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.font = Theme.bodyFont
        textView.isScrollEnabled = false
        textView.backgroundColor = Theme.background
        textView.layer.cornerRadius = 19
        textView.layer.borderWidth = 1
        textView.layer.borderColor = Theme.separator.cgColor
        textView.textContainerInset = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardAppearance = .light
        textView.returnKeyType = .default
        addSubview(textView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "Сообщение…"
        placeholderLabel.font = Theme.bodyFont
        placeholderLabel.textColor = Theme.secondaryText
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setTitle("↑", for: .normal)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.titleLabel?.font = UIFont.systemFont(ofSize: 21, weight: .bold)
        sendButton.backgroundColor = Theme.accent
        sendButton.layer.cornerRadius = 19
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        addSubview(sendButton)

        textViewHeight = textView.heightAnchor.constraint(equalToConstant: minHeight)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textViewHeight,

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 13),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 9),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -8),

            sendButton.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: -2),
            sendButton.widthAnchor.constraint(equalToConstant: 38),
            sendButton.heightAnchor.constraint(equalToConstant: 38)
        ])

        updateSendButton()
    }

    func clear() {
        textView.text = ""
        textViewDidChange(textView)
    }

    func focus() {
        textView.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func sendTapped() {
        if isStreaming {
            delegate?.composerDidRequestStop(self)
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        textView.text = ""
        textViewDidChange(textView)
        delegate?.composer(self, didSend: trimmed)
    }

    private func updateSendButton() {
        if isStreaming {
            sendButton.setTitle("■", for: .normal)
            sendButton.backgroundColor = Theme.danger
            sendButton.isEnabled = true
            sendButton.alpha = 1.0
        } else {
            sendButton.setTitle("↑", for: .normal)
            sendButton.backgroundColor = Theme.accent
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            sendButton.isEnabled = hasText
            sendButton.alpha = hasText ? 1.0 : 0.45
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
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateHeight()
        updateSendButton()
    }
}
