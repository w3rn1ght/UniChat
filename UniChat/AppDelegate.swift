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
            window.overrideUserInterfaceStyle = .light
        }
        window.makeKeyAndVisible()
        self.window = window

        return true
    }
}
