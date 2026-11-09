import UIKit

protocol ComposerViewDelegate: AnyObject {
    func composer(_ composer: ComposerView, didSend text: String)
    func composerDidRequestStop(_ composer: ComposerView)
}

final class ComposerView: UIView, UITextViewDelegate {

    weak var delegate: ComposerViewDelegate?

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private var textViewHeight: NSLayoutConstraint!

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

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.font = Theme.bodyFont
        textView.isScrollEnabled = false
        textView.backgroundColor = Theme.surfaceContainer
        textView.layer.cornerRadius = 24
        if #available(iOS 13.0, *) {
            textView.layer.cornerCurve = .continuous
        }
        textView.layer.borderWidth = 0
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 15, bottom: 11, right: 15)
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
        sendButton.setTitleColor(Theme.onAccent, for: .normal)
        sendButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        sendButton.backgroundColor = Theme.accent
        sendButton.layer.cornerRadius = 22
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        addSubview(sendButton)

        textViewHeight = textView.heightAnchor.constraint(equalToConstant: minHeight)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textViewHeight,

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

        delegate?.composer(self, didSend: trimmed)
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
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            sendButton.backgroundColor = hasText ? Theme.accent : Theme.surfaceContainerHigh
            sendButton.setTitleColor(hasText ? Theme.onAccent : Theme.secondaryText, for: .normal)
            sendButton.isEnabled = hasText
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
