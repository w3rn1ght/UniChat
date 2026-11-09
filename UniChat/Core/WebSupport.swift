import UIKit
import WebKit

/// Общие настройки встроенного браузера для входа в аккаунты.
enum WebSupport {

    /// Представляемся мобильным Safari той же версии, что и система.
    /// Если выдавать себя за iOS 17, Google отдаёт современные сценарии
    /// (passkeys, новые API), которых нет в WebKit на iOS 12 — из-за этого
    /// кнопка «Далее» может не реагировать. Более старый UA включает
    /// совместимый (ES5) вариант страницы входа.
    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 12_5_7 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1"

    /// Небольшой набор API, которых нет в WebKit на iOS 12, но которые
    /// используют современные страницы входа Google. Без них JavaScript
    /// может остановиться до обработчика кнопки «Далее».
    private static let compatSource = """
    (function() {
      try {
        if (typeof globalThis === 'undefined') { window.globalThis = window; }
      } catch (e) {}

      try {
        if (!navigator.languages || navigator.languages.length === 0) {
          Object.defineProperty(navigator, 'languages', {
            get: function() { return ['ru-RU', 'ru', 'en-US', 'en']; }
          });
        }
      } catch (e) {}

      try {
        if (!window.isSecureContext) { window.isSecureContext = true; }
      } catch (e) {}

      if (typeof window.queueMicrotask !== 'function') {
        window.queueMicrotask = function(fn) {
          Promise.resolve().then(fn).catch(function(err) { setTimeout(function() { throw err; }, 0); });
        };
      }

      if (typeof window.requestIdleCallback !== 'function') {
        window.requestIdleCallback = function(fn) {
          var start = Date.now();
          return setTimeout(function() {
            fn({ didTimeout: false, timeRemaining: function() { return Math.max(0, 50 - (Date.now() - start)); } });
          }, 1);
        };
      }
      if (typeof window.cancelIdleCallback !== 'function') {
        window.cancelIdleCallback = function(id) { clearTimeout(id); };
      }

      if (window.Promise) {
        if (typeof Promise.allSettled !== 'function') {
          Promise.allSettled = function(list) {
            return Promise.all(Array.prototype.map.call(list, function(item) {
              return Promise.resolve(item).then(function(value) {
                return { status: 'fulfilled', value: value };
              }, function(reason) {
                return { status: 'rejected', reason: reason };
              });
            }));
          };
        }
        if (typeof Promise.any !== 'function') {
          Promise.any = function(list) {
            return new Promise(function(resolve, reject) {
              var items = Array.prototype.slice.call(list);
              if (!items.length) { reject(new Error('All promises were rejected')); return; }
              var rejected = 0;
              items.forEach(function(item) {
                Promise.resolve(item).then(resolve, function() {
                  rejected += 1;
                  if (rejected === items.length) { reject(new Error('All promises were rejected')); }
                });
              });
            });
          };
        }
      }

      if (typeof Object.fromEntries !== 'function') {
        Object.fromEntries = function(entries) {
          var result = {};
          var list = Array.prototype.slice.call(entries || []);
          for (var i = 0; i < list.length; i++) {
            result[list[i][0]] = list[i][1];
          }
          return result;
        };
      }
      if (typeof Object.hasOwn !== 'function') {
        Object.hasOwn = function(object, key) {
          return Object.prototype.hasOwnProperty.call(object, key);
        };
      }

      if (typeof Array.prototype.at !== 'function') {
        Object.defineProperty(Array.prototype, 'at', {
          value: function(index) {
            if (index < 0) { index += this.length; }
            return index < 0 || index >= this.length ? undefined : this[index];
          },
          writable: true, configurable: true
        });
      }
      if (typeof String.prototype.at !== 'function') {
        Object.defineProperty(String.prototype, 'at', {
          value: function(index) {
            if (index < 0) { index += this.length; }
            return index < 0 || index >= this.length ? undefined : this.charAt(index);
          },
          writable: true, configurable: true
        });
      }
      if (typeof Array.prototype.flat !== 'function') {
        Object.defineProperty(Array.prototype, 'flat', {
          value: function(depth) {
            var level = depth === undefined ? 1 : Number(depth);
            function flatten(input, current) {
              var out = [];
              for (var i = 0; i < input.length; i++) {
                var value = input[i];
                if (Array.isArray(value) && current > 0) {
                  out = out.concat(flatten(value, current - 1));
                } else {
                  out.push(value);
                }
              }
              return out;
            }
            return flatten(this, isFinite(level) ? level : 1);
          },
          writable: true, configurable: true
        });
      }
      if (typeof Array.prototype.flatMap !== 'function') {
        Object.defineProperty(Array.prototype, 'flatMap', {
          value: function(fn, thisArg) {
            return Array.prototype.flat.call(Array.prototype.map.call(this, fn, thisArg), 1);
          },
          writable: true, configurable: true
        });
      }
      if (typeof Array.prototype.findLast !== 'function') {
        Object.defineProperty(Array.prototype, 'findLast', {
          value: function(fn, thisArg) {
            for (var i = this.length - 1; i >= 0; i--) {
              if (fn.call(thisArg, this[i], i, this)) { return this[i]; }
            }
            return undefined;
          },
          writable: true, configurable: true
        });
      }

      if (typeof String.prototype.replaceAll !== 'function') {
        Object.defineProperty(String.prototype, 'replaceAll', {
          value: function(search, replacement) {
            if (search instanceof RegExp) {
              if (!search.global) { throw new TypeError('replaceAll must be called with a global RegExp'); }
              return this.replace(search, replacement);
            }
            return this.split(String(search)).join(String(replacement));
          },
          writable: true, configurable: true
        });
      }
      if (typeof String.prototype.matchAll !== 'function') {
        Object.defineProperty(String.prototype, 'matchAll', {
          value: function(regexp) {
            var source = regexp instanceof RegExp ? regexp : new RegExp(regexp, 'g');
            if (!source.global) { throw new TypeError('matchAll must be called with a global RegExp'); }
            var flags = source.flags || 'g';
            if (flags.indexOf('g') < 0) { flags += 'g'; }
            var clone = new RegExp(source.source, flags);
            var text = String(this);
            var matches = [];
            var match;
            while ((match = clone.exec(text)) !== null) {
              matches.push(match);
              if (match[0] === '') { clone.lastIndex += 1; }
            }
            return matches[Symbol.iterator]();
          },
          writable: true, configurable: true
        });
      }

      if (!Element.prototype.toggleAttribute) {
        Element.prototype.toggleAttribute = function(name, force) {
          var has = this.hasAttribute(name);
          var next = force === undefined ? !has : !!force;
          if (next && !has) { this.setAttribute(name, ''); }
          if (!next && has) { this.removeAttribute(name); }
          return next;
        };
      }
      if (!Element.prototype.replaceChildren) {
        Element.prototype.replaceChildren = function() {
          while (this.firstChild) { this.removeChild(this.firstChild); }
          for (var i = 0; i < arguments.length; i++) {
            var node = arguments[i];
            this.appendChild(node instanceof Node ? node : document.createTextNode(String(node)));
          }
        };
      }
      if (!Element.prototype.getAttributeNames) {
        Element.prototype.getAttributeNames = function() {
          var names = [];
          for (var i = 0; i < this.attributes.length; i++) { names.push(this.attributes[i].name); }
          return names;
        };
      }

      // Web Animations API, ResizeObserver, IntersectionObserver and
      // PerformanceObserver намеренно не подменяются: в настоящем Safari 12
      // их тоже нет, и страницы Google используют собственные fallback-ветки.
      // Некорректные заглушки могут «подвесить» анимации и кнопку «Далее».

      if (window.crypto && !window.crypto.randomUUID) {
        try {
          Object.defineProperty(window.crypto, 'randomUUID', {
            value: function() {
              var bytes = new Uint8Array(16);
              if (window.crypto.getRandomValues) { window.crypto.getRandomValues(bytes); }
              else { for (var i = 0; i < 16; i++) { bytes[i] = Math.floor(Math.random() * 256); } }
              bytes[6] = (bytes[6] & 15) | 64;
              bytes[8] = (bytes[8] & 63) | 128;
              var hex = [];
              for (var j = 0; j < 16; j++) {
                hex.push((bytes[j] + 256).toString(16).substr(1));
              }
              return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-' +
                hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-' +
                hex.slice(10, 16).join('');
            },
            configurable: true
          });
        } catch (e) {}
      }

      if (!window.structuredClone) {
        window.structuredClone = function(value) {
          if (value === undefined || value === null) { return value; }
          try { return JSON.parse(JSON.stringify(value)); } catch (e) { return value; }
        };
      }

      if (window.URLSearchParams && !URLSearchParams.prototype.sort) {
        URLSearchParams.prototype.sort = function() {
          var pairs = [];
          this.forEach(function(value, key) { pairs.push([key, value]); });
          pairs.sort(function(a, b) { return a[0] < b[0] ? -1 : (a[0] > b[0] ? 1 : 0); });
          var self = this;
          pairs.forEach(function(pair) {
            self.delete(pair[0]);
            self.append(pair[0], pair[1]);
          });
        };
      }

      if (typeof window.reportError !== 'function') {
        window.reportError = function(error) {
          try { console.error(error); } catch (e) {}
        };
      }
    })();
    """

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(WKUserScript(source: compatSource,
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
        let store = WKWebsiteDataStore.default()

        guard !domains.isEmpty else {
            store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                completion?()
            }
            return
        }

        let hosts = domains.map { domain -> String in
            var value = domain.lowercased()
            if value.hasPrefix("https://") { value = String(value.dropFirst(8)) }
            if value.hasPrefix("http://") { value = String(value.dropFirst(7)) }
            while value.hasSuffix("/") { value.removeLast() }
            return value
        }

        store.fetchDataRecords(ofTypes: types) { records in
            let matched = records.filter { record in
                let name = record.displayName.lowercased()
                return hosts.contains { host in
                    return name == host || name.hasSuffix("." + host) || host.hasSuffix("." + name)
                }
            }
            store.removeData(ofTypes: types, for: matched) {
                completion?()
            }
        }
    }
}
