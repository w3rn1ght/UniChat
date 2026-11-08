import Foundation
import UIKit
import WebKit

/// Вычисляет DeepSeekHashV1 (proof-of-work) в скрытом WKWebView.
///
/// DeepSeek использует собственную Keccak-разновидность, поэтому честно
/// повторить её в Swift нельзя. Зато можно взять официальный WASM-модуль
/// DeepSeek и вызвать его так же, как это делает сайт.
final class DeepSeekPoWSolver: NSObject, WKNavigationDelegate {

    static let shared = DeepSeekPoWSolver()

    private var webView: WKWebView?
    private var isReady = false
    private var isPreparing = false
    private var isSolving = false
    private var waiters: [(Bool) -> Void] = []

    private override init() {
        super.init()
    }

    func solve(challenge: [String: Any],
               completion: @escaping (Result<Int, Error>) -> Void) {

        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.solve(challenge: challenge, completion: completion)
            }
            return
        }

        guard let value = challenge["challenge"] as? String, !value.isEmpty,
              let salt = challenge["salt"] as? String,
              let expireAt = numberValue(challenge["expire_at"]),
              let difficulty = numberValue(challenge["difficulty"]) else {
            completion(.failure(ChatError(message: "DeepSeek вернул некорректную PoW-задачу.")))
            return
        }

        let payload: [String: Any] = [
            "challenge": value,
            "salt": salt,
            "expire_at": expireAt,
            "difficulty": difficulty
        ]

        ensureReady { [weak self] ready in
            guard let self = self else { return }
            guard ready, let webView = self.webView else {
                completion(.failure(ChatError(message: "Не удалось запустить вычислитель DeepSeek.")))
                return
            }
            guard !self.isSolving else {
                completion(.failure(ChatError(message: "Предыдущая PoW-задача ещё вычисляется.")))
                return
            }

            self.isSolving = true
            let script = "window.__unichatSolve(" + WebSupport.jsonString(payload) + ")"
            webView.evaluateJavaScript(script) { result, error in
                self.isSolving = false

                if let error = error {
                    completion(.failure(ChatError(message: "PoW DeepSeek: " + error.localizedDescription)))
                    return
                }
                if let number = result as? NSNumber {
                    completion(.success(number.intValue))
                    return
                }
                if let number = result as? Double {
                    completion(.success(Int(number)))
                    return
                }
                if let number = result as? Int {
                    completion(.success(number))
                    return
                }
                completion(.failure(ChatError(message: "PoW DeepSeek не вернул ответ.")))
            }
        }
    }

    private func numberValue(_ value: Any?) -> NSNumber? {
        if let number = value as? NSNumber { return number }
        if let text = value as? String, let double = Double(text) { return NSNumber(value: double) }
        return nil
    }

    // MARK: - Подготовка WebView

    private func ensureReady(_ completion: @escaping (Bool) -> Void) {
        if isReady {
            completion(true)
            return
        }

        waiters.append(completion)
        if isPreparing { return }
        isPreparing = true

        guard let url = Bundle.main.url(forResource: "deepseek_pow", withExtension: "wasm"),
              let data = try? Data(contentsOf: url) else {
            finishPrepare(false)
            return
        }

        let base64 = data.base64EncodedString()
        let html = makeHTML(base64: base64)
        let webView = WKWebView(frame: CGRect(x: -20, y: -20, width: 1, height: 1),
                                configuration: WebSupport.makeConfiguration())
        webView.navigationDelegate = self
        webView.alpha = 0.01
        webView.isUserInteractionEnabled = false
        self.webView = webView

        if let window = WebSupport.activeWindow {
            window.addSubview(webView)
        }
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func finishPrepare(_ success: Bool) {
        isPreparing = false
        isReady = success
        let list = waiters
        waiters.removeAll()
        for waiter in list {
            waiter(success)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isPreparing {
            finishPrepare(true)
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        if isPreparing {
            finishPrepare(false)
        }
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        if isPreparing {
            finishPrepare(false)
        }
    }

    private func makeHTML(base64: String) -> String {
        return """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"></head>
        <body>
        <script>
        (function() {
          var bytes = (function(b64) {
            var binary = atob(b64);
            var result = new Uint8Array(binary.length);
            for (var i = 0; i < binary.length; i++) { result[i] = binary.charCodeAt(i); }
            return result;
          })("\(base64)");
          var module = new WebAssembly.Module(bytes);
          var instance = new WebAssembly.Instance(module, { wbg: {} });
          var e = instance.exports;
          var encoder = new TextEncoder();

          function hashText(text) {
            var ret = e.__wbindgen_add_to_stack_pointer(-16);
            var input = encoder.encode(text);
            var ptr = e.__wbindgen_export_0(input.length, 1) >>> 0;
            new Uint8Array(e.memory.buffer, ptr, input.length).set(input);
            e.wasm_deepseek_hash_v1(ret, ptr, input.length);
            var view = new DataView(e.memory.buffer);
            var outPtr = view.getInt32(ret, true);
            var outLen = view.getInt32(ret + 4, true);
            var out = new Uint8Array(e.memory.buffer, outPtr, outLen);
            var result = '';
            for (var i = 0; i < out.length; i++) { result += String.fromCharCode(out[i]); }
            e.__wbindgen_add_to_stack_pointer(16);
            return result;
          }

          window.__unichatSolve = function(ch) {
            if (typeof e.wasm_solve === 'function') {
              var challengeBytes = encoder.encode(ch.challenge);
              var prefixBytes = encoder.encode(ch.salt + '_' + ch.expire_at + '_');
              var cPtr = e.__wbindgen_export_0(challengeBytes.length, 1) >>> 0;
              var pPtr = e.__wbindgen_export_0(prefixBytes.length, 1) >>> 0;
              new Uint8Array(e.memory.buffer, cPtr, challengeBytes.length).set(challengeBytes);
              new Uint8Array(e.memory.buffer, pPtr, prefixBytes.length).set(prefixBytes);
              var stack = e.__wbindgen_add_to_stack_pointer(-16);
              e.wasm_solve(stack, cPtr, challengeBytes.length, pPtr, prefixBytes.length, ch.difficulty);
              var dataView = new DataView(e.memory.buffer);
              var code = dataView.getInt32(stack, true);
              var answer = dataView.getFloat64(stack + 8, true);
              e.__wbindgen_add_to_stack_pointer(16);
              if (code === 0 || !isFinite(answer) || answer < 0) {
                throw new Error('no solution');
              }
              return Math.floor(answer);
            }

            var prefix = ch.salt + '_' + ch.expire_at + '_';
            for (var i = 0; i < ch.difficulty; i++) {
              if (hashText(prefix + i) === ch.challenge) { return i; }
            }
            throw new Error('no solution');
          };
        })();
        </script>
        </body>
        </html>
        """
    }
}
