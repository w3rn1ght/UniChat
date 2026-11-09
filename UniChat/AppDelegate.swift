import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        Theme.configureAppearance()
        AppSettings.shared.load()
        ConversationStore.shared.load()

        let root = ConversationsViewController()
        let navigation = UINavigationController(rootViewController: root)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        if #available(iOS 13.0, *) {
            window.overrideUserInterfaceStyle = Theme.isDark ? .dark : .light
        }
        window.backgroundColor = Theme.surface
        window.makeKeyAndVisible()
        self.window = window

        applyTheme(resetRoot: false)

        return true
    }

    /// Применяет сохранённую тему ко всему окну. При смене режима корневой
    /// экран пересобирается, чтобы все цвета обновились без перезапуска.
    func applyTheme(resetRoot: Bool, completion: (() -> Void)? = nil) {
        Theme.configureAppearance()
        UIApplication.shared.statusBarStyle = Theme.isDark ? .lightContent : .default

        if #available(iOS 13.0, *) {
            window?.overrideUserInterfaceStyle = Theme.isDark ? .dark : .light
        }
        window?.backgroundColor = Theme.surface

        guard resetRoot, let window = window else {
            completion?()
            return
        }

        let root = ConversationsViewController()
        let navigation = UINavigationController(rootViewController: root)
        UIView.transition(with: window,
                          duration: 0.22,
                          options: .transitionCrossDissolve,
                          animations: {
                              window.rootViewController = navigation
                          },
                          completion: { _ in completion?() })
    }
}
