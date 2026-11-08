import UIKit

final class MessageCell: UITableViewCell {

    static let reuseIdentifier = "MessageCell"

    private let bubbleView = UIView()
    private let stackView = UIStackView()
    private let headerLabel = UILabel()
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
        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.masksToBounds = true
        contentView.addSubview(bubbleView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 3
        bubbleView.addSubview(stackView)

        headerLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        headerLabel.textColor = Theme.secondaryText
        headerLabel.numberOfLines = 1
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        messageLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        stackView.addArrangedSubview(headerLabel)
        stackView.addArrangedSubview(messageLabel)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.86),

            stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 13),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -13),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        ])
    }

    func configure(with message: ChatMessage, providerTitle: String?, streaming: Bool) {
        let isUser = message.role == .user

        leadingConstraint.isActive = !isUser
        trailingConstraint.isActive = isUser

        if isUser {
            bubbleView.backgroundColor = Theme.outgoingBubble
        } else if message.isError {
            bubbleView.backgroundColor = UIColor(red: 1.0, green: 0.95, blue: 0.95, alpha: 1.0)
        } else {
            bubbleView.backgroundColor = Theme.incomingBubble
        }

        if isUser {
            bubbleView.layer.borderWidth = 0
        } else {
            bubbleView.layer.borderWidth = 1
            bubbleView.layer.borderColor = (message.isError ? Theme.danger.withAlphaComponent(0.3) : Theme.separator).cgColor
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
            textColor = UIColor.white
        } else if message.isError {
            textColor = Theme.danger
        } else {
            textColor = Theme.primaryText
        }

        var displayText = message.text
        if streaming {
            displayText = displayText.isEmpty ? "▍" : displayText + " ▍"
        }
        messageLabel.attributedText = Markdown.render(displayText, color: textColor)
        messageLabel.accessibilityLabel = displayText
    }

    func updateStreamingText(_ text: String, providerTitle: String?, isError: Bool) {
        let displayText = text.isEmpty ? "▍" : text + " ▍"
        messageLabel.attributedText = Markdown.render(displayText,
                                                   color: isError ? Theme.danger : Theme.primaryText)
        headerLabel.text = isError ? "Ошибка" : (providerTitle ?? "Ассистент")
        headerLabel.textColor = isError ? Theme.danger : Theme.secondaryText
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        headerLabel.isHidden = false
        headerLabel.text = nil
        messageLabel.attributedText = nil
    }
}
