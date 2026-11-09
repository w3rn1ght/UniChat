import UIKit

/// Ячейка-карточка: скруглённая поверхность с отступами от краёв таблицы.
class CardCell: UITableViewCell {

    let cardView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCard()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCard() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = Theme.card
        cardView.layer.cornerRadius = Theme.cornerLarge
        if #available(iOS 13.0, *) {
            cardView.layer.cornerCurve = .continuous
        }
        cardView.clipsToBounds = true
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                              constant: Theme.cardInset),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                               constant: -Theme.cardInset)
        ])
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: animated ? 0.12 : 0) {
            self.cardView.backgroundColor = highlighted
                ? Theme.surfaceContainerHigh
                : Theme.card
        }
    }
}

/// Круглая тональная «иконка» с буквой или символом.
final class CircleBadgeView: UIView {

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.masksToBounds = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    func configure(text: String, background: UIColor, foreground: UIColor, fontSize: CGFloat = 16) {
        label.text = text
        label.textColor = foreground
        label.font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        backgroundColor = background
    }
}

/// Универсальная строка Material 3: карточка, тональный значок, заголовок,
/// подпись, дополнительный текст и шеврон.
final class MaterialRowCell: CardCell {

    static let reuseIdentifier = "MaterialRowCell"

    private let badge = CircleBadgeView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let accessoryLabel = UILabel()
    private let chevronLabel = UILabel()
    private let textStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupRow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupRow() {
        accessoryLabel.translatesAutoresizingMaskIntoConstraints = false
        accessoryLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        accessoryLabel.textColor = Theme.secondaryText
        accessoryLabel.textAlignment = .right
        cardView.addSubview(accessoryLabel)

        chevronLabel.translatesAutoresizingMaskIntoConstraints = false
        chevronLabel.text = "›"
        chevronLabel.font = UIFont.systemFont(ofSize: 24, weight: .regular)
        chevronLabel.textColor = Theme.outline
        chevronLabel.textAlignment = .center
        cardView.addSubview(chevronLabel)

        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .fill
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        cardView.addSubview(textStack)

        cardView.addSubview(badge)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            badge.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 40),
            badge.heightAnchor.constraint(equalToConstant: 40),

            textStack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 9),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -9),

            chevronLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            chevronLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevronLabel.widthAnchor.constraint(equalToConstant: 18),

            accessoryLabel.trailingAnchor.constraint(equalTo: chevronLabel.leadingAnchor, constant: -4),
            accessoryLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            accessoryLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 92)
        ])

        textStack.trailingAnchor.constraint(equalTo: accessoryLabel.leadingAnchor,
                                            constant: -8).isActive = true
    }

    func configure(badgeText: String,
                   badgeBackground: UIColor,
                   badgeForeground: UIColor,
                   badgeFontSize: CGFloat = 16,
                   title: String,
                   subtitle: String?,
                   accessory: String? = nil,
                   titleColor: UIColor = Theme.primaryText,
                   showsChevron: Bool = true) {
        badge.configure(text: badgeText,
                        background: badgeBackground,
                        foreground: badgeForeground,
                        fontSize: badgeFontSize)
        titleLabel.text = title
        titleLabel.textColor = titleColor
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty
        accessoryLabel.text = accessory
        accessoryLabel.isHidden = (accessory ?? "").isEmpty
        chevronLabel.isHidden = !showsChevron
        accessoryLabel.isHidden = (accessory ?? "").isEmpty || !showsChevron
    }
}

/// Ячейка с текстом по центру: «Проверить подключение», «Удалить».
final class MaterialActionCell: CardCell {

    private let actionLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        actionLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        actionLabel.textAlignment = .center
        cardView.addSubview(actionLabel)

        NSLayoutConstraint.activate([
            actionLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            actionLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            actionLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, color: UIColor) {
        actionLabel.text = title
        actionLabel.textColor = color
    }
}
