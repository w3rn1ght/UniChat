import UIKit

/// Палитра и типографика в духе Material You (Material 3).
///
/// iOS 12 не умеет динамические системные цвета, поэтому режим хранится
/// в UserDefaults. При переключении темы приложение пересобирает корневой
/// экран — так все цвета применяются сразу и без «полу-тёмных» элементов.
enum Theme {

    // MARK: - Режим

    private static let modeKey = "unichat.theme.mode"

    /// Тёмная тема включена?
    static var isDark: Bool {
        get { return UserDefaults.standard.string(forKey: modeKey) == "dark" }
        set { UserDefaults.standard.set(newValue ? "dark" : "light", forKey: modeKey) }
    }

    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> UIColor {
        return isDark ? dark : light
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    // MARK: - Цвета

    static var accent: UIColor {
        return dynamic(rgb(0.404, 0.314, 0.643), rgb(0.816, 0.737, 1.0)) // #6750A4 / #D0BCFF
    }
    static var accentSoft: UIColor {
        return dynamic(rgb(0.918, 0.867, 1.0), rgb(0.310, 0.216, 0.545)) // #EADDFF / #4F378B
    }
    static var onAccent: UIColor {
        return dynamic(.white, rgb(0.220, 0.118, 0.447)) // white / #381E72
    }
    static var primaryContainer: UIColor {
        return dynamic(rgb(0.918, 0.867, 1.0), rgb(0.310, 0.216, 0.545))
    }
    static var onPrimaryContainer: UIColor {
        return dynamic(rgb(0.129, 0.0, 0.365), rgb(0.918, 0.867, 1.0))
    }
    static var secondary: UIColor {
        return dynamic(rgb(0.384, 0.357, 0.443), rgb(0.800, 0.761, 0.863))
    }
    static var secondaryContainer: UIColor {
        return dynamic(rgb(0.910, 0.871, 0.973), rgb(0.290, 0.267, 0.345))
    }
    static var onSecondaryContainer: UIColor {
        return dynamic(rgb(0.114, 0.098, 0.169), rgb(0.910, 0.871, 0.973))
    }
    static var tertiary: UIColor {
        return dynamic(rgb(0.490, 0.322, 0.376), rgb(0.937, 0.722, 0.784))
    }
    static var tertiaryContainer: UIColor {
        return dynamic(rgb(1.0, 0.847, 0.894), rgb(0.388, 0.231, 0.282))
    }

    static var background: UIColor {
        return dynamic(rgb(0.996, 0.969, 1.0), rgb(0.078, 0.071, 0.094)) // #FEF7FF / #141218
    }
    static var surface: UIColor { return background }
    static var card: UIColor {
        return dynamic(.white, rgb(0.114, 0.106, 0.125)) // #FFFFFF / #1D1B20
    }
    static var surfaceContainer: UIColor {
        return dynamic(rgb(0.953, 0.929, 0.969), rgb(0.129, 0.122, 0.149)) // #F3EDF7 / #211F26
    }
    static var surfaceContainerHigh: UIColor {
        return dynamic(rgb(0.925, 0.902, 0.941), rgb(0.169, 0.161, 0.188)) // #ECE6F0 / #2B2930
    }
    static var surfaceVariant: UIColor {
        return dynamic(rgb(0.906, 0.878, 0.925), rgb(0.286, 0.271, 0.310)) // #E7E0EC / #49454F
    }

    static var incomingBubble: UIColor {
        return dynamic(rgb(0.953, 0.929, 0.969), rgb(0.129, 0.122, 0.149))
    }
    static var outgoingBubble: UIColor {
        return dynamic(rgb(0.404, 0.314, 0.643), rgb(0.310, 0.216, 0.545))
    }
    static var onOutgoingBubble: UIColor {
        return dynamic(.white, rgb(0.918, 0.867, 1.0))
    }
    static var primaryText: UIColor {
        return dynamic(rgb(0.114, 0.106, 0.125), rgb(0.902, 0.878, 0.914)) // #1D1B20 / #E6E0E9
    }
    static var secondaryText: UIColor {
        return dynamic(rgb(0.286, 0.271, 0.310), rgb(0.792, 0.769, 0.816)) // #49454F / #CAC4D0
    }
    static var outline: UIColor {
        return dynamic(rgb(0.475, 0.455, 0.494), rgb(0.576, 0.561, 0.600)) // #79747E / #938F99
    }
    static var separator: UIColor {
        return dynamic(rgb(0.792, 0.769, 0.816), rgb(0.286, 0.271, 0.310)) // #CAC4D0 / #49454F
    }
    static var danger: UIColor {
        return dynamic(rgb(0.702, 0.149, 0.118), rgb(1.0, 0.706, 0.671)) // #B3261E / #FFB4AB
    }
    static var dangerContainer: UIColor {
        return dynamic(rgb(0.976, 0.871, 0.863), rgb(0.549, 0.114, 0.094))
    }
    static var success: UIColor {
        return dynamic(rgb(0.220, 0.416, 0.125), rgb(0.718, 0.953, 0.592)) // #386A20 / #B7F397
    }
    static var successContainer: UIColor {
        return dynamic(rgb(0.827, 0.906, 0.847), rgb(0.118, 0.227, 0.102))
    }
    static var warning: UIColor {
        return dynamic(rgb(0.478, 0.349, 0.0), rgb(0.961, 0.843, 0.478)) // #7A5900 / #F5D77A
    }

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
        navigationBar.barStyle = isDark ? .black : .default
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

        UISwitch.appearance().onTintColor = accent
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
                            color: UIColor? = nil,
                            opacity: Float = 0.10,
                            radius: CGFloat = 10,
                            offset: CGSize = CGSize(width: 0, height: 4)) {
        let shadowColor = color ?? (isDark
            ? UIColor.black
            : UIColor(red: 0.129, green: 0.0, blue: 0.365, alpha: 1.0))
        view.layer.shadowColor = shadowColor.cgColor
        view.layer.shadowOpacity = opacity
        view.layer.shadowRadius = radius
        view.layer.shadowOffset = offset
        view.layer.masksToBounds = false
    }

    static func toneColor(for index: Int) -> UIColor {
        let lightTones: [UIColor] = [
            rgb(0.918, 0.867, 1.0),
            rgb(0.910, 0.871, 0.973),
            rgb(1.0, 0.847, 0.894),
            rgb(0.827, 0.906, 0.847),
            rgb(1.0, 0.902, 0.812)
        ]
        let darkTones: [UIColor] = [
            rgb(0.310, 0.216, 0.545),
            rgb(0.290, 0.267, 0.345),
            rgb(0.388, 0.231, 0.282),
            rgb(0.118, 0.227, 0.102),
            rgb(0.360, 0.251, 0.180)
        ]
        let tones = isDark ? darkTones : lightTones
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
