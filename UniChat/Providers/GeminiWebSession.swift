import Foundation
import UIKit
import WebKit

/// Описание выбранной модели Gemini для веб-запроса.
struct GeminiModelOption {
    let modelId: String
    let modelNumber: Int
    let capacityTail: Int
    let thinking: Bool

    static let auto = GeminiModelOption(modelId: "", modelNumber: 0, capacityTail: 0, thinking: false)

    static func from(_ raw: String) -> GeminiModelOption {
        let name = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let thinking = name.contains("thinking") || name.contains("think")

        if name.isEmpty || name == "auto" || name == "default" {
            return .auto
        }

        if name.contains("lite") {
            if name.contains("advanced") {
                return GeminiModelOption(modelId: "8c46e95b1a07cecc", modelNumber: 6, capacityTail: 2, thinking: thinking)
            }
            if name.contains("plus") {
                return GeminiModelOption(modelId: "8c46e95b1a07cecc", modelNumber: 6, capacityTail: 4, thinking: thinking)
            }
            return GeminiModelOption(modelId: "cf41b0e0dd7d53e5", modelNumber: 6, capacityTail: 1, thinking: thinking)
        }

        if name.contains("pro") {
            if name.contains("advanced") {
                return GeminiModelOption(modelId: "e6fa609c3fa255c0", modelNumber: 3, capacityTail: 2, thinking: thinking)
            }
            if name.contains("plus") {
                return GeminiModelOption(modelId: "e6fa609c3fa255c0", modelNumber: 3, capacityTail: 4, thinking: thinking)
            }
            return GeminiModelOption(modelId: "9d8ca3786ebdfbea", modelNumber: 3, capacityTail: 1, thinking: thinking)
        }

        if name.contains("flash") {
            if name.contains("advanced") {
                return GeminiModelOption(modelId: "56fdd199312815e2", modelNumber: 1, capacityTail: 2, thinking: thinking)
            }
            if name.contains("plus") {
                return GeminiModelOption(modelId: "56fdd199312815e2", modelNumber: 1, capacityTail: 4, thinking: thinking)
            }
            return GeminiModelOption(modelId: "fbb127bbb056c959", modelNumber: 1, capacityTail: 1, thinking: thinking)
        }

        return .auto
    }
}

/// Один активный запрос к Gemini внутри WKWebView.
final class GeminiActiveRequest: CancellableTask {

    let id: String
    var prompt: String
    var model: GeminiModelOption
    var retried = false
    var receivedText = false
    private(set) var cancelled = false
    private(set) var finished = false

    var onDelta: ((String) -> Void)?
    var onFinish: ((Error?) -> Void)?
    var onCancel: (() -> Void)?

    init(id: String, prompt: String, model: GeminiModelOption) {
        self.id = id
        self.prompt = prompt
        self.model = model
    }

    func emit(_ text: String) {
        guard !cancelled, !finished, !text.isEmpty else { return }
        DispatchQueue.main.async {
            guard !self.cancelled, !self.finished else { return }
            self.onDelta?(text)
        }
    }

    func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async {
            let callback = self.onFinish
            self.onFinish = nil
            self.onDelta = nil
            callback?(error)
        }
    }

    func cancel() {
        guard !finished else { return }
        cancelled = true
        onCancel?()
        finish(ChatError(message: "Запрос отменён."))
    }
}

/// Держит один залогиненный WKWebView с Gemini и выполняет StreamGenerate
/// прямо на домене gemini.google.com. Так браузер сам отправляет cookie,
/// включая защищённые HttpOnly-сессии Google.
final class GeminiWebSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    static let shared = GeminiWebSession()

    private var webView: WKWebView?
    private var isReady = false
    private var isPreparing = false
    private var prepareWaiters: [(Result<Void, Error>) -> Void] = []
    private var prepareTimeout: DispatchWorkItem?
    private var activeRequest: GeminiActiveRequest?

    private override init() {
        super.init()
    }

    // MARK: - Подготовка

    func prepare(completion: @escaping (Result<Void, Error>) -> Void) {
        onMain {
            if self.isReady {
                completion(.success(()))
                return
            }

            self.prepareWaiters.append(completion)
            if self.isPreparing { return }

            self.isPreparing = true
            self.startLoading()
            self.scheduleTimeout()
        }
    }

    func testConnection(completion: @escaping (Result<String, Error>) -> Void) {
        prepare { result in
            switch result {
            case .success:
                completion(.success("Аккаунт Gemini подключён."))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Сбрасывает страницу и состояние после смены аккаунта.
    func invalidate() {
        onMain {
            self.isReady = false
            self.isPreparing = false
            self.prepareTimeout?.cancel()
            self.prepareTimeout = nil

            let waiters = self.prepareWaiters
            self.prepareWaiters.removeAll()
            for waiter in waiters {
                waiter(.failure(ChatError(message: "Сессия Gemini обновлена. Попробуйте ещё раз.")))
            }

            self.activeRequest?.finish(ChatError(message: "Сессия Gemini обновлена."))
            self.activeRequest = nil

            self.webView?.stopLoading()
            self.webView?.removeFromSuperview()
            self.webView = nil
        }
    }

    private func startLoading() {
        let view = ensureWebView()
        isReady = false

        guard let url = URL(string: "https://gemini.google.com/app") else {
            finishPrepare(.failure(ChatError(message: "Некорректный адрес Gemini.")))
            return
        }

        let request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 60)
        view.load(request)
        pollReadiness(after: 0.8)
    }

    private func pollReadiness(after delay: TimeInterval) {
        guard isPreparing else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isPreparing else { return }
            guard let view = self.webView else { return }

            let script = """
            (function() {
              try {
                var w = window.WIZ_global_data;
                if (w && w.SNlM0e && String(w.SNlM0e).length > 10) { return 'ready'; }
                var html = document.documentElement ? document.documentElement.innerHTML : '';
                if (/"SNlM0e":"[^"]{10,}"/.test(html)) { return 'ready'; }
                return 'wait';
              } catch (e) { return 'wait'; }
            })()
            """

            view.evaluateJavaScript(script) { result, _ in
                guard self.isPreparing else { return }
                if let value = result as? String, value == "ready" {
                    self.finishPrepare(.success(()))
                } else {
                    self.pollReadiness(after: 1.0)
                }
            }
        }
    }

    private func scheduleTimeout() {
        prepareTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPreparing else { return }
            self.finishPrepare(.failure(ChatError(
                message: "Не удалось открыть Gemini. Проверьте интернет/VPN и войдите в аккаунт."
            )))
        }
        prepareTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 40, execute: item)
    }

    private func finishPrepare(_ result: Result<Void, Error>) {
        guard isPreparing else { return }
        isPreparing = false
        prepareTimeout?.cancel()
        prepareTimeout = nil

        switch result {
        case .success:
            isReady = true
        case .failure:
            isReady = false
        }

        let waiters = prepareWaiters
        prepareWaiters.removeAll()
        for waiter in waiters {
            waiter(result)
        }
    }

    private func ensureWebView() -> WKWebView {
        if let view = webView { return view }

        let configuration = WebSupport.makeConfiguration()
        configuration.userContentController.add(self, name: "unichat")

        let view = WKWebView(frame: CGRect(x: -20, y: -20, width: 1, height: 1),
                             configuration: configuration)
        view.customUserAgent = WebSupport.safariUserAgent
        view.navigationDelegate = self
        view.uiDelegate = self
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        webView = view

        if let window = WebSupport.activeWindow {
            window.addSubview(view)
        }
        return view
    }

    // MARK: - Запрос

    func stream(prompt: String,
                model: GeminiModelOption,
                onDelta: @escaping (String) -> Void,
                onFinish: @escaping (Error?) -> Void) -> CancellableTask? {

        let id = UUID().uuidString
        let token = GeminiActiveRequest(id: id, prompt: prompt, model: model)
        token.onDelta = onDelta
        token.onFinish = { [weak self] error in
            if let self = self, self.activeRequest?.id == id {
                self.activeRequest = nil
            }
            onFinish(error)
        }
        token.onCancel = { [weak self] in
            guard let self = self, let view = self.webView else { return }
            let escaped = id.replacingOccurrences(of: "'", with: "\\'")
            view.evaluateJavaScript("window.UniChatGemini && window.UniChatGemini.cancel('\(escaped)')",
                                    completionHandler: nil)
        }

        onMain {
            if self.activeRequest != nil {
                token.finish(ChatError(message: "Предыдущий запрос Gemini ещё выполняется."))
                return
            }

            self.activeRequest = token
            self.prepare { [weak self] result in
                guard let self = self else { return }
                if token.cancelled {
                    if self.activeRequest?.id == id { self.activeRequest = nil }
                    return
                }

                switch result {
                case .failure(let error):
                    self.activeRequest = nil
                    token.finish(error)
                case .success:
                    self.startGeneration(token: token)
                }
            }
        }

        return token
    }

    fileprivate func startGeneration(token: GeminiActiveRequest) {
        guard let view = webView else {
            token.finish(ChatError(message: "Gemini WebView недоступен."))
            return
        }
        guard !token.cancelled, !token.finished else { return }

        var config: [String: Any] = [
            "id": token.id,
            "prompt": token.prompt,
            "language": GeminiWebSession.languageCode,
            "thinking": token.model.thinking
        ]
        if !token.model.modelId.isEmpty {
            config["modelId"] = token.model.modelId
            config["modelNumber"] = token.model.modelNumber
            config["capacityTail"] = token.model.capacityTail
        }

        let script = GeminiWebSession.script
            + "\nwindow.UniChatGemini.start("
            + WebSupport.jsonString(config)
            + ");"

        view.evaluateJavaScript(script) { [weak self] _, error in
            if let error = error {
                if let self = self, self.activeRequest?.id == token.id {
                    self.activeRequest = nil
                }
                token.finish(ChatError(message: "Gemini: не удалось запустить запрос. " + error.localizedDescription))
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
            if !token.finished {
                token.finish(ChatError(message: "Gemini не ответил за 3 минуты. Попробуйте ещё раз."))
            }
        }
    }

    private func markDisconnected() {
        isReady = false
        DispatchQueue.main.async {
            let all = AppSettings.shared.providers
            for provider in all where provider.kind == .geminiAccount {
                var updated = provider
                updated.accountConnected = false
                updated.accountEmail = ""
                AppSettings.shared.upsert(updated)
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "unichat",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let id = body["id"] as? String,
              let token = activeRequest,
              token.id == id,
              !token.finished,
              !token.cancelled else {
            return
        }

        switch type {
        case "delta":
            if let text = body["text"] as? String, !text.isEmpty {
                token.receivedText = true
                token.emit(text)
            }

        case "reset":
            if let text = body["text"] as? String {
                token.receivedText = true
                token.emit("\u{0}" + text)
            }

        case "done":
            let finalText = body["text"] as? String ?? ""
            if !token.receivedText && !finalText.isEmpty {
                token.receivedText = true
                token.emit(finalText)
            }
            if token.receivedText {
                token.finish(nil)
            } else {
                token.finish(ChatError(message: "Gemini вернул пустой ответ."))
            }

        case "error":
            let text = body["message"] as? String ?? "Ошибка Gemini."
            let code = (body["code"] as? NSNumber)?.intValue ?? 0

            if code == 1052 && !token.retried && !token.receivedText {
                token.retried = true
                token.model = .auto
                startGeneration(token: token)
                return
            }

            if code == 401 || code == 403 || text.contains("Сессия Gemini") {
                markDisconnected()
            }
            token.finish(ChatError(message: text))

        default:
            break
        }
    }

    // MARK: - Навигация

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isPreparing {
            pollReadiness(after: 0.2)
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        if isPreparing {
            finishPrepare(.failure(ChatError.network(error)))
        }
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if isPreparing {
            finishPrepare(.failure(ChatError.network(error)))
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
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        completionHandler(defaultText)
    }

    // MARK: - Вспомогательное

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    static var languageCode: String {
        let raw = Locale.preferredLanguages.first ?? "ru"
        let code = raw.components(separatedBy: "-").first ?? "ru"
        return code.isEmpty ? "ru" : code
    }

    // MARK: - JavaScript

    private static let script = #"""
    (function() {
      if (window.UniChatGemini) { return; }

      var active = {};

      function post(object) {
        try {
          window.webkit.messageHandlers.unichat.postMessage(object);
        } catch (e) {}
      }

      function wizData() {
        if (window.WIZ_global_data) { return window.WIZ_global_data; }
        var result = {};
        try {
          var html = document.documentElement ? document.documentElement.innerHTML : '';
          var at = html.match(/"SNlM0e":"([^"]*)"/);
          if (at) { result.SNlM0e = at[1]; }
          var sid = html.match(/"FdrFJe":"([^"]*)"/);
          if (sid) { result.FdrFJe = sid[1]; }
        } catch (e) {}
        return result;
      }

      function newUUID() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
          var r = Math.random() * 16 | 0;
          var v = c === 'x' ? r : (r & 0x3 | 0x8);
          return v.toString(16);
        }).toUpperCase();
      }

      function errorFor(code) {
        switch (code) {
          case 1013: return 'Временная ошибка Gemini (1013). Попробуйте ещё раз.';
          case 1037: return 'Закончился лимит Gemini для этой модели. Выберите другую модель или подождите.';
          case 1050: return 'Модель не совпадает с историей чата. Начните новый чат.';
          case 1052: return 'Модель недоступна для этого аккаунта. Выберите другую модель.';
          case 1060: return 'Google временно заблокировал IP. Попробуйте VPN или подождите.';
          default: return 'Gemini вернул ошибку ' + code + '.';
        }
      }

      function finish(state, error, code) {
        if (state.done) { return; }
        state.done = true;
        delete active[state.id];
        if (error) {
          post({ type: 'error', id: state.id, message: error, code: code || 0 });
        } else {
          post({ type: 'done', id: state.id, text: state.lastText || '' });
        }
      }

      function handlePart(state, part) {
        if (!part) { return; }

        try {
          var errorCode = part[5] && part[5][2] && part[5][2][0] && part[5][2][0][1] && part[5][2][0][1][0];
          if (errorCode) {
            state.errorCode = errorCode;
            state.error = errorFor(errorCode);
            try { if (state.xhr) { state.xhr.abort(); } } catch (e) {}
            finish(state, state.error, errorCode);
            return;
          }
        } catch (e) {}

        var inner = part[2];
        if (typeof inner !== 'string' || !inner) { return; }

        var payload;
        try { payload = JSON.parse(inner); } catch (e) { return; }

        var candidates = payload[4];
        if (!candidates || !candidates.length) { return; }

        for (var i = 0; i < candidates.length; i++) {
          var candidate = candidates[i];
          if (!candidate) { continue; }

          var rcid = candidate[0] || ('idx_' + i);
          var text = '';
          try {
            if (candidate[1] && typeof candidate[1][0] === 'string') {
              text = candidate[1][0];
            }
          } catch (e) {}

          text = text.replace(/https?:\/\/googleusercontent\.com\/(?:\w+\/)+\d+\n*/g, '');

          var previous = state.texts[rcid] || '';
          if (text.length > previous.length && text.indexOf(previous) === 0) {
            post({ type: 'delta', id: state.id, text: text.slice(previous.length) });
            state.lastText = text;
            state.sawText = true;
          } else if (text && text !== previous) {
            post({ type: 'reset', id: state.id, text: text });
            state.lastText = text;
            state.sawText = true;
          }
          state.texts[rcid] = text;
        }
      }

      function consume(state, text) {
        state.buffer += text;

        if (!state.prefixChecked) {
          var prefix = ")]}'";
          if (state.buffer.length < prefix.length && prefix.indexOf(state.buffer) === 0) {
            return;
          }
          if (state.buffer.indexOf(prefix) === 0) {
            state.buffer = state.buffer.slice(prefix.length);
          }
          state.buffer = state.buffer.replace(/^\s+/, '');
          state.prefixChecked = true;
        }

        while (true) {
          state.buffer = state.buffer.replace(/^\s+/, '');
          var marker = state.buffer.match(/^(\d+)\n/);
          if (!marker) { return; }

          var length = parseInt(marker[1], 10);
          var start = marker[0].length;
          if (state.buffer.length < start + length) { return; }

          var frame = state.buffer.substr(start, length);
          state.buffer = state.buffer.slice(start + length);
          if (!frame.replace(/\s/g, '')) { continue; }

          var parsed;
          try { parsed = JSON.parse(frame); } catch (e) { continue; }
          var parts = Object.prototype.toString.call(parsed) === '[object Array]' ? parsed : [parsed];
          for (var i = 0; i < parts.length; i++) {
            if (state.done) { return; }
            handlePart(state, parts[i]);
          }
        }
      }

      window.UniChatGemini = {
        ready: function() {
          var data = wizData();
          return !!(data && data.SNlM0e && String(data.SNlM0e).length > 10);
        },

        start: function(config) {
          var state = {
            id: config.id,
            buffer: '',
            prefixChecked: false,
            texts: {},
            lastText: '',
            sawText: false,
            done: false,
            error: null,
            errorCode: 0,
            xhr: null
          };
          active[state.id] = state;

          var data = wizData();
          var at = data && data.SNlM0e ? String(data.SNlM0e) : '';
          var sessionID = data && data.FdrFJe ? String(data.FdrFJe) : '';
          if (!at) {
            finish(state, 'Сессия Gemini не найдена. Войдите в аккаунт снова.', 401);
            return;
          }

          var reqid = Math.floor(Math.random() * 800000) + 100000;
          var inner = new Array(81);
          for (var i = 0; i < inner.length; i++) { inner[i] = null; }

          inner[0] = [config.prompt, 0, null, null, null, null, 0];
          inner[1] = [config.language || 'ru'];
          inner[2] = ['', '', '', null, null, null, null, null, null, ''];
          inner[6] = [1];
          inner[7] = 1;
          inner[10] = 1;
          inner[11] = 0;
          inner[17] = [[0]];
          inner[18] = 0;
          inner[27] = 1;
          inner[30] = [4];
          inner[41] = [1];
          inner[53] = 0;
          inner[59] = newUUID();
          inner[61] = [];
          inner[68] = 1;
          inner[79] = 1;
          inner[80] = 1;

          var headers = {
            'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
            'Origin': 'https://gemini.google.com',
            'Referer': 'https://gemini.google.com/',
            'X-Same-Domain': '1',
            'x-goog-ext-525005358-jspb': '["' + inner[59] + '",1]'
          };

          if (config.modelId && config.modelNumber) {
            var modelHeader = [1, null, null, null, config.modelId, null, null, 0,
                               [4, 5, 6, 8], null, null, config.capacityTail || 1,
                               null, null, config.modelNumber];
            modelHeader.push(config.thinking ? 2 : 1);
            modelHeader.push(sessionID);
            headers['x-goog-ext-525001261-jspb'] = JSON.stringify(modelHeader);
            headers['x-goog-ext-73010989-jspb'] = '[0]';
            headers['x-goog-ext-73010990-jspb'] = '[0,0,0]';
            inner[79] = config.modelNumber;
            inner[80] = config.thinking ? 2 : 1;
          }

          var body = 'at=' + encodeURIComponent(at)
            + '&f.req=' + encodeURIComponent(JSON.stringify([null, JSON.stringify(inner)]));
          var url = 'https://gemini.google.com/_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate'
            + '?hl=' + encodeURIComponent(config.language || 'ru')
            + '&_reqid=' + reqid
            + '&rt=c';
          if (sessionID) {
            url += '&f.sid=' + encodeURIComponent(sessionID);
          }

          var xhr = new XMLHttpRequest();
          state.xhr = xhr;
          xhr.open('POST', url, true);
          xhr.withCredentials = true;
          for (var key in headers) {
            try { xhr.setRequestHeader(key, headers[key]); } catch (e) {}
          }

          var seen = 0;
          function consumeResponse() {
            var text = '';
            try { text = xhr.responseText || ''; } catch (e) { return; }
            if (text.length > seen) {
              var chunk = text.slice(seen);
              seen = text.length;
              consume(state, chunk);
            }
          }

          xhr.onprogress = consumeResponse;
          xhr.onreadystatechange = function() {
            if (xhr.readyState >= 3) { consumeResponse(); }
          };
          xhr.onload = function() {
            consumeResponse();
            if (state.done) { return; }

            var responseURL = '';
            try { responseURL = xhr.responseURL || ''; } catch (e) {}
            if (responseURL.indexOf('accounts.google.com') >= 0) {
              finish(state, 'Сессия Gemini истекла. Войдите в аккаунт снова.', 401);
              return;
            }

            if (xhr.status === 401 || xhr.status === 403) {
              finish(state, 'Сессия Gemini истекла. Войдите в аккаунт снова.', xhr.status);
              return;
            }
            if (xhr.status === 429) {
              finish(state, 'Слишком много запросов к Gemini. Подождите немного.', 429);
              return;
            }
            if (xhr.status >= 400) {
              finish(state, 'Gemini HTTP ' + xhr.status + '.', xhr.status);
              return;
            }
            if (xhr.status === 0) {
              finish(state, 'Сетевая ошибка Gemini.', 0);
              return;
            }
            if (!state.sawText) {
              finish(state, 'Gemini не вернул текст. Попробуйте ещё раз.', 0);
              return;
            }
            finish(state, null, 0);
          };
          xhr.onerror = function() {
            finish(state, 'Сетевая ошибка Gemini.', 0);
          };
          xhr.ontimeout = function() {
            finish(state, 'Таймаут Gemini.', 0);
          };

          xhr.timeout = 180000;
          xhr.send(body);
        },

        cancel: function(id) {
          var state = active[id];
          if (!state) { return; }
          try { if (state.xhr) { state.xhr.abort(); } } catch (e) {}
          finish(state, null, 0);
        }
      };
    })();
    """#
}
