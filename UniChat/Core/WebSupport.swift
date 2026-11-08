import UIKit
import WebKit

/// Общие настройки встроенного браузера для входа в аккаунты.
enum WebSupport {

    /// Представляемся мобильным Safari: некоторые страницы Google иначе
    /// считают WKWebView небезопасным браузером.
    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"

    private static let stealthSource = """
    (function() {
      try {
        if (!navigator.languages || navigator.languages.length === 0) {
          Object.defineProperty(navigator, 'languages', {
            get: function() { return ['ru-RU', 'ru', 'en-US', 'en']; }
          });
        }
      } catch (e) {}
    })();
    """

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(WKUserScript(source: stealthSource,
                                                                        injectionTime: .atDocumentStart,
                                                                        forMainFrameOnly: false))
        return configuration
    }

    static func makeWebView() -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1),
                                configuration: makeConfiguration())
        webView.customUserAgent = safariUserAgent
        return webView
    }

    static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }

    /// Окно, к которому можно временно прикрепить скрытый WKWebView.
    static var activeWindow: UIWindow? {
        if let window = UIApplication.shared.keyWindow {
            return window
        }
        for window in UIApplication.shared.windows where window.isKeyWindow {
            return window
        }
        return UIApplication.shared.windows.first
    }

    static func clearData(for domains: [String], completion: (() -> Void)? = nil) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        var urls: [URL] = []
        for domain in domains {
            if let url = URL(string: domain) {
                urls.append(url)
            }
        }

        let store = WKWebsiteDataStore.default()
        if urls.isEmpty {
            store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                completion?()
            }
        } else {
            store.removeData(ofTypes: types, for: urls, modifiedSince: Date(timeIntervalSince1970: 0)) {
                completion?()
            }
        }
    }
}
