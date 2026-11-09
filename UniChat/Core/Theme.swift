import UIKit

/// Палитра и типографика в духе Material You (Material 3).
///
/// iOS 12 не умеет динамические системные цвета, поэтому используется
/// фиксированная светлая схема с выразительным фиолетовым seed-цветом.
enum Theme {

    // MARK: - Цвета

    static let accent = UIColor(red: 0.404, green: 0.314, blue: 0.643, alpha: 1.0)      // #6750A4
    static let accentSoft = UIColor(red: 0.918, green: 0.867, blue: 1.0, alpha: 1.0)    // #EADDFF
    static let onAccent = UIColor.white
    static let primaryContainer = UIColor(red: 0.918, green: 0.867, blue: 1.0, alpha: 1.0)
    static let onPrimaryContainer = UIColor(red: 0.129, green: 0.0, blue: 0.365, alpha: 1.0) // #21005D
    static let secondary = UIColor(red: 0.384, green: 0.357, blue: 0.443, alpha: 1.0)   // #625B71
    static let secondaryContainer = UIColor(red: 0.910, green: 0.871, blue: 0.973, alpha: 1.0) // #E8DEF8
    static let onSecondaryContainer = UIColor(red: 0.114, green: 0.098, blue: 0.169, alpha: 1.0)
    static let tertiary = UIColor(red: 0.490, green: 0.322, blue: 0.376, alpha: 1.0)    // #7D5260
    static let tertiaryContainer = UIColor(red: 1.0, green: 0.847, blue: 0.894, alpha: 1.0)

    static let background = UIColor(red: 0.996, green: 0.969, blue: 1.0, alpha: 1.0)    // #FEF7FF
    static let surface = background
    static let card = UIColor.white
    static let surfaceContainer = UIColor(red: 0.953, green: 0.929, blue: 0.969, alpha: 1.0) // #F3EDF7
    static let surfaceContainerHigh = UIColor(red: 0.925, green: 0.902, blue: 0.941, alpha: 1.0) // #ECE6F0
    static let surfaceVariant = UIColor(red: 0.906, green: 0.878, blue: 0.925, alpha: 1.0) // #E7E0EC

    static let incomingBubble = UIColor(red: 0.953, green: 0.929, blue: 0.969, alpha: 1.0)
    static let outgoingBubble = accent
    static let primaryText = UIColor(red: 0.114, green: 0.106, blue: 0.125, alpha: 1.0) // #1D1B20
    static let secondaryText = UIColor(red: 0.286, green: 0.271, blue: 0.310, alpha: 1.0) // #49454F
    static let outline = UIColor(red: 0.475, green: 0.455, blue: 0.494, alpha: 1.0)     // #79747E
    static let separator = UIColor(red: 0.792, green: 0.769, blue: 0.816, alpha: 1.0)   // #CAC4D0
    static let danger = UIColor(red: 0.702, green: 0.149, blue: 0.118, alpha: 1.0)      // #B3261E
    static let dangerContainer = UIColor(red: 0.976, green: 0.871, blue: 0.863, alpha: 1.0)
    static let success = UIColor(red: 0.220, green: 0.416, blue: 0.125, alpha: 1.0)     // #386A20
    static let warning = UIColor(red: 0.478, green: 0.349, blue: 0.0, alpha: 1.0)       // #7A5900

    // MARK: - Геометрия

    static let cornerExtraLarge: CGFloat = 28.0
    static let cornerLarge: CGFloat = 20.0
    static let cornerMedium: CGFloat = 16.0
    static let cornerSmall: CGFloat = 12.0
    static let cardInset: CGFloat = 16.0

    // MARK: - Типографика

    static let fontSize: CGFloat = 16.0

    static var bodyFont: UIFont {
        return UIFont.systemFont(ofSize: fontSize)
    }

    static var boldFont: UIFont {
        return UIFont.systemFont(ofSize: fontSize, weight: .semibold)
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

    static func headline(_ size: CGFloat = 24) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: .bold)
    }

    static func title(_ size: CGFloat = 16) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func label(_ size: CGFloat = 12) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: .medium)
    }

    // MARK: - Оформление

    static func configureAppearance() {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = surface
        navigationBar.backgroundColor = surface
        navigationBar.tintColor = accent
        navigationBar.prefersLargeTitles = true
        navigationBar.titleTextAttributes = [
            .foregroundColor: primaryText,
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold)
        ]
        if #available(iOS 11.0, *) {
            navigationBar.largeTitleTextAttributes = [
                .foregroundColor: primaryText,
                .font: UIFont.systemFont(ofSize: 30, weight: .bold)
            ]
        }
        navigationBar.shadowImage = UIImage()
        navigationBar.setBackgroundImage(UIImage(), for: .default)

        let tableView = UITableView.appearance()
        tableView.separatorColor = .clear
        tableView.backgroundColor = surface

        let searchBar = UISearchBar.appearance()
        searchBar.tintColor = accent
        searchBar.barTintColor = surface
    }

    static func applyCardStyle(_ view: UIView, radius: CGFloat = cornerLarge, color: UIColor = card) {
        view.backgroundColor = color
        view.layer.cornerRadius = radius
        if #available(iOS 13.0, *) {
            view.layer.cornerCurve = .continuous
        }
        view.clipsToBounds = true
    }

    static func applyShadow(_ view: UIView,
                            color: UIColor = UIColor(red: 0.129, green: 0.0, blue: 0.365, alpha: 1.0),
                            opacity: Float = 0.10,
                            radius: CGFloat = 10,
                            offset: CGSize = CGSize(width: 0, height: 4)) {
        view.layer.shadowColor = color.cgColor
        view.layer.shadowOpacity = opacity
        view.layer.shadowRadius = radius
        view.layer.shadowOffset = offset
        view.layer.masksToBounds = false
    }

    static func toneColor(for index: Int) -> UIColor {
        let tones: [UIColor] = [
            UIColor(red: 0.918, green: 0.867, blue: 1.0, alpha: 1.0),
            UIColor(red: 0.910, green: 0.871, blue: 0.973, alpha: 1.0),
            UIColor(red: 1.0, green: 0.847, blue: 0.894, alpha: 1.0),
            UIColor(red: 0.827, green: 0.906, blue: 0.847, alpha: 1.0),
            UIColor(red: 1.0, green: 0.902, blue: 0.812, alpha: 1.0)
        ]
        return tones[abs(index) % tones.count]
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
