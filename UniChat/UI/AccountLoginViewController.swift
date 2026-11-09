import UIKit
import WebKit

/// Вход в аккаунты DeepSeek и Gemini через настоящий сайт.
///
/// Пароли вводятся только на странице провайдера внутри WKWebView.
/// Приложение не видит и не хранит их. Для DeepSeek сохраняется токен
/// сессии из localStorage, для Gemini — cookie-сессия самого WebKit.
final class AccountLoginViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private var provider: ProviderConfig
    private let onUpdate: (ProviderConfig) -> Void

    private let webView: WKWebView
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)

    private var pollTimer: Timer?
    private var pollCount = 0
    private var isFinishing = false
    private var isChecking = false

    init(provider: ProviderConfig, onUpdate: @escaping (ProviderConfig) -> Void) {
        self.provider = provider
        self.onUpdate = onUpdate
        self.webView = WKWebView(frame: .zero, configuration: WebSupport.makeConfiguration())
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pollTimer?.invalidate()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = provider.kind == .deepSeekAccount ? "Вход в DeepSeek" : "Вход в Gemini"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = Theme.surface

        let doneItem = UIBarButtonItem(title: "Готово",
                                       style: .done,
                                       target: self,
                                       action: #selector(manualCheck))
        let resetItem = UIBarButtonItem(title: "Сброс",
                                        style: .plain,
                                        target: self,
                                        action: #selector(confirmReset))
        navigationItem.rightBarButtonItems = [resetItem, doneItem]
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть",
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(closeTapped))

        setupHeader()
        setupWebView()
        startLoading()
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            stopPolling()
        }
    }

    // MARK: - UI

    private func setupHeader() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = Theme.surface
        view.addSubview(header)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = Theme.primaryText
        statusLabel.numberOfLines = 2
        header.addSubview(statusLabel)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = UIFont.systemFont(ofSize: 12)
        hintLabel.textColor = Theme.secondaryText
        hintLabel.numberOfLines = 0
        header.addSubview(hintLabel)

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = Theme.accent
        progress.trackTintColor = Theme.separator
        progress.progress = 0
        view.addSubview(progress)

        var hint: String
        switch provider.kind {
        case .deepSeekAccount:
            hint = "Войдите на chat.deepseek.com любым способом. Приложение само заберёт токен сессии — пароль останется на сайте DeepSeek."
        case .geminiAccount:
            hint = "Войдите в Google-аккаунт на gemini.google.com. Сессия сохраняется в приложении. Если Google не пускает встроенный браузер, используйте API-ключ."
        default:
            hint = ""
        }

        if !provider.accountEmail.isEmpty {
            statusLabel.text = "Подключено: " + provider.accountEmail
        } else {
            statusLabel.text = "Ожидаем вход…"
        }
        hintLabel.text = hint

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            statusLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            hintLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            hintLabel.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -10),

            progress.topAnchor.constraint(equalTo: header.bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2)
        ])

        header.tag = 500
    }

    private func setupWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.customUserAgent = WebSupport.safariUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = Theme.background
        webView.isOpaque = true
        view.addSubview(webView)

        let topView: UIView = view.viewWithTag(500) ?? view

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topView.bottomAnchor, constant: 2),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Загрузка

    private func startLoading() {
        let address: String
        switch provider.kind {
        case .deepSeekAccount:
            address = "https://chat.deepseek.com/"
        case .geminiAccount:
            address = "https://gemini.google.com/app"
        default:
            address = "https://gemini.google.com/app"
        }

        guard let url = URL(string: address) else { return }
        webView.load(URLRequest(url: url))
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollCount = 0
        let timer = Timer.scheduledTimer(timeInterval: 1.5,
                                         target: self,
                                         selector: #selector(pollTick),
                                         userInfo: nil,
                                         repeats: true)
        pollTimer = timer
        pollTick()
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func pollTick() {
        guard !isFinishing, !isChecking else { return }

        // На странице входа Google не трогаем DOM: там большой документ,
        // а постоянная сериализация мешает кнопке «Далее» и вводу почты.
        guard isRelevantHost else { return }

        pollCount += 1
        if pollCount > 360 {
            stopPolling()
            statusLabel.text = "Вход не завершён"
            statusLabel.textColor = Theme.danger
            return
        }
        checkAccount(manual: false)
    }

    private var isRelevantHost: Bool {
        let host = (webView.url?.host ?? "").lowercased()
        guard !host.isEmpty else { return false }
        if provider.kind == .deepSeekAccount {
            return host == "deepseek.com" || host.hasSuffix(".deepseek.com")
        }
        return host == "gemini.google.com" || host.hasSuffix(".gemini.google.com")
    }

    @objc private func manualCheck() {
        view.endEditing(true)
        checkAccount(manual: true)
    }

    @objc private func closeTapped() {
        view.endEditing(true)
        stopPolling()
        navigationController?.popViewController(animated: true)
    }

    private func setStatus(_ text: String, error: Bool = false) {
        statusLabel.text = text
        statusLabel.textColor = error ? Theme.danger : Theme.primaryText
    }

    // MARK: - Проверка входа

    private func checkAccount(manual: Bool) {
        isChecking = true
        if provider.kind == .deepSeekAccount {
            checkDeepSeek(manual: manual)
        } else {
            checkGemini(manual: manual)
        }
    }

    private func finishChecking() {
        isChecking = false
    }

    private func checkDeepSeek(manual: Bool) {
        let script = """
        (function() {
          try {
            var raw = localStorage.getItem('userToken');
            if (!raw) { return ''; }
            try {
              var obj = JSON.parse(raw);
              if (obj && typeof obj.value === 'string') { return obj.value; }
            } catch (e) {
              if (typeof raw === 'string' && raw.length > 20) { return raw; }
            }
          } catch (e) {}
          return '';
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self = self else { return }
            guard let token = result as? String, token.count > 20 else {
                self.finishChecking()
                if manual {
                    self.setStatus("Пока не вижу вход. Завершите вход на сайте.", error: true)
                }
                return
            }

            self.isFinishing = true
            self.stopPolling()
            self.setStatus("Вход найден. Проверяем аккаунт…")
            self.saveDeepSeek(token: token)
        }
    }

    private func checkGemini(manual: Bool) {
        let script = """
        (function() {
          try {
            var w = window.WIZ_global_data;
            if (w && w.SNlM0e && String(w.SNlM0e).length > 10) { return 'ready'; }
          } catch (e) {}
          try {
            var html = document.documentElement ? document.documentElement.innerHTML : '';
            if (/"SNlM0e"\\s*:\\s*"[^"]{10,}"/.test(html)) { return 'ready'; }
          } catch (e) {}
          return '';
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self = self else { return }
            guard let value = result as? String, value == "ready" else {
                self.finishChecking()
                if manual {
                    self.setStatus("Вход не найден. Завершите вход в Google на сайте.", error: true)
                }
                return
            }

            self.isFinishing = true
            self.stopPolling()
            self.setStatus("Вход найден. Проверяем аккаунт…")
            self.saveGemini()
        }
    }

    private func saveDeepSeek(token: String) {
        provider.accountToken = token
        provider.accountConnected = true
        if provider.accountEmail.isEmpty {
            provider.accountEmail = "Аккаунт DeepSeek"
        }
        AppSettings.shared.upsert(provider)
        onUpdate(provider)

        let tester = DeepSeekAccountProvider(config: provider)
        tester.testConnection { [weak self] result in
            guard let self = self else { return }
            self.finishChecking()

            let latest = AppSettings.shared.provider(id: self.provider.id) ?? self.provider
            self.provider = latest
            self.onUpdate(latest)

            switch result {
            case .success(let message):
                self.setStatus(message)
                self.showSuccess(message: message)
            case .failure(let error):
                if latest.trimmedAccountToken.isEmpty {
                    self.isFinishing = false
                    self.setStatus("DeepSeek не принял вход. Попробуйте войти заново.", error: true)
                    self.startPolling()
                } else {
                    self.setStatus("Токен сохранён, но проверка не удалась.")
                    self.showSuccess(message: "Вход сохранён, но проверка профиля не удалась: " + error.localizedDescription)
                }
            }
        }
    }

    private func saveGemini() {
        provider.accountConnected = true
        if provider.accountEmail.isEmpty {
            provider.accountEmail = "Аккаунт Gemini"
        }
        AppSettings.shared.upsert(provider)
        onUpdate(provider)
        GeminiWebSession.shared.invalidate()

        GeminiWebSession.shared.testConnection { [weak self] result in
            guard let self = self else { return }
            self.finishChecking()

            switch result {
            case .success(let message):
                self.setStatus(message)
                self.showSuccess(message: message)
            case .failure(let error):
                self.setStatus("Вход сохранён, проверка не удалась.", error: false)
                self.showSuccess(message: "Вход сохранён, но проверить Gemini сейчас не удалось: "
                    + error.localizedDescription)
            }
        }
    }

    private func showSuccess(message: String) {
        guard presentedViewController == nil, view.window != nil else { return }
        presentSuccessAlert(title: "Готово", message: message) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    private func presentSuccessAlert(title: String, message: String, completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard self.view.window != nil else {
                completion()
                return
            }
            guard self.presentedViewController == nil else {
                completion()
                return
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completion()
            })
            self.present(alert, animated: true, completion: nil)
        }
    }

    // MARK: - Сброс

    @objc private func confirmReset() {
        let alert = UIAlertController(title: "Выйти из аккаунта?",
                                      message: "Будут удалены cookie сайта и сохранённый токен.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Выйти", style: .destructive) { _ in
            self.resetAccount()
        })
        present(alert, animated: true, completion: nil)
    }

    private func resetAccount() {
        isFinishing = true
        stopPolling()
        setStatus("Выходим из аккаунта…")

        provider.accountConnected = false
        provider.accountEmail = ""
        provider.accountToken = ""
        AppSettings.shared.upsert(provider)
        onUpdate(provider)

        let domains: [String]
        if provider.kind == .deepSeekAccount {
            domains = ["https://chat.deepseek.com", "https://deepseek.com"]
        } else {
            GeminiWebSession.shared.invalidate()
            domains = [
                "https://gemini.google.com",
                "https://accounts.google.com",
                "https://google.com"
            ]
        }

        WebSupport.clearData(for: domains) { [weak self] in
            guard let self = self else { return }
            self.isFinishing = false
            self.setStatus("Вы вышли из аккаунта.")
            self.startLoading()
            self.startPolling()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progress.setProgress(0.1, animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress.setProgress(1.0, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.progress.setProgress(0, animated: false)
        }
        if !isFinishing && isRelevantHost {
            checkAccount(manual: false)
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        progress.setProgress(0, animated: false)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        progress.setProgress(0, animated: false)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        setStatus("Не удалось загрузить страницу входа.", error: true)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        if scheme == "http" || scheme == "https" || scheme == "about" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true, completion: nil)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true, completion: nil)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true, completion: nil)
    }
}
