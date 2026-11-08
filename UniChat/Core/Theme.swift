import UIKit

enum Theme {

    static let accent = UIColor(red: 0.36, green: 0.42, blue: 0.95, alpha: 1.0)
    static let accentSoft = UIColor(red: 0.36, green: 0.42, blue: 0.95, alpha: 0.12)
    static let background = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
    static let card = UIColor.white
    static let incomingBubble = UIColor.white
    static let outgoingBubble = accent
    static let primaryText = UIColor(white: 0.11, alpha: 1.0)
    static let secondaryText = UIColor(white: 0.46, alpha: 1.0)
    static let separator = UIColor(white: 0.88, alpha: 1.0)
    static let danger = UIColor(red: 0.82, green: 0.22, blue: 0.24, alpha: 1.0)

    static let fontSize: CGFloat = 16.0

    static var bodyFont: UIFont {
        return UIFont.systemFont(ofSize: fontSize)
    }

    static var boldFont: UIFont {
        return UIFont.boldSystemFont(ofSize: fontSize)
    }

    static var italicFont: UIFont {
        let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor
        if let italic = descriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: italic, size: fontSize)
        }
        return UIFont.italicSystemFont(ofSize: fontSize)
    }

    static var monoFont: UIFont {
        return UIFont(name: "Menlo", size: 13.5)
            ?? UIFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .regular)
    }

    static func configureAppearance() {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = card
        navigationBar.tintColor = accent
        navigationBar.titleTextAttributes = [
            .foregroundColor: primaryText,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigationBar.shadowImage = UIImage()
        navigationBar.setBackgroundImage(UIImage(), for: .default)

        let tableView = UITableView.appearance()
        tableView.separatorColor = separator
    }

    static func dateString(_ date: Date) -> String {
        return shortDateFormatter.string(from: date)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()
}
