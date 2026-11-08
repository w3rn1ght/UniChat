# UniChat — ИИ-клиент для iOS 12+

Нативный клиент чата с ИИ на UIKit. Работает с DeepSeek и Gemini через
обычный вход в аккаунт, а также с OpenAI-совместимыми API
(OpenRouter, AnyModel, DeepSeek, свои шлюзы) и Gemini API по ключу.
Работает на iOS 12.0 и новее, без сторонних зависимостей.

## Возможности

- Два режима доступа: вход в аккаунт DeepSeek/Gemini или API-ключ.
- Стриминг ответов (SSE) и отмена запроса.
- Несколько провайдеров, переключение на лету, выбор модели.
- Markdown в ответах: жирный, курсив, код, ссылки, списки, заголовки.
- История чатов сохраняется локально (Application Support).
- API-ключи и токены — в Keychain; cookie аккаунтов — в хранилище WebKit.
- Свой Base URL и дополнительные заголовки для любого провайдера.
- Проверка подключения прямо в настройках.
- Тёмная тема не поддерживается осознанно: iOS 12 её не имеет, интерфейс светлый.

## Требования

- macOS с Xcode. Для deployment target 12.0 подойдут Xcode 13–16.
  В самых новых Xcode минимальная версия iOS может быть выше — тогда
  поднимите `IPHONEOS_DEPLOYMENT_TARGET`, но код совместим и с iOS 13–18.
- Устройство или симулятор с iOS 12+.
- Аккаунт разработчика не обязателен для симулятора.

## Сборка

1. Откройте `UniChat.xcodeproj`.
2. Выберите таргет `UniChat` → Signing & Capabilities:
   - укажите свою Team (или `None` для симулятора);
   - при желании смените Bundle Identifier `com.unichat.app`.
3. Выберите симулятор (например, iPhone 8, iOS 12) и нажмите Run.

Проект создан вручную, без CocoaPods/SPM. Все исходники лежат в `UniChat/`.

## Сборка на GitHub Actions

В репозитории уже есть workflow `.github/workflows/build-ios.yml`:

- запускается на `macos-15` с Xcode 16.4;
- собирает `Release` под `iphoneos` без подписи;
- подписывает бинарник `ldid` с entitlements из `ci/entitlements.plist`
  (чтобы работал Keychain на джейлбрейке);
- упаковывает `UniChat-unsigned.ipa` и `UniChat.deb`;
- выкладывает их в артефакты сборки, а при пуше тега `v*` — в GitHub Release.

Запуск: Actions → «Build iOS app (unsigned IPA + DEB)» → Run workflow.

## Установка на джейлбрейк (iOS 12)

**Вариант 1 — .deb (рекомендуется)**
1. Скачайте `UniChat.deb` из артефактов или Release.
2. Откройте файл в Sileo/Zebra/Filza и установите (или `dpkg -i UniChat.deb`).
3. Приложение появится на домашнем экране: `uicache` вызывается в postinst.

**Вариант 2 — IPA**
1. Скачайте `UniChat-unsigned.ipa`.
2. Установите через AppSync Unified + Filza/ipainstaller,
   либо переподпишите своим сертификатом (AltStore/Sideloadly).
3. На iOS 12 без AppSync неподписанный IPA не установится.

Keychain: если iOS отклонит Keychain для неподписанной сборки (ошибка -34018),
ключи автоматически сохранятся в UserDefaults. На ldid-подписанной сборке
используется обычный Keychain.


## Провайдеры из коробки

| Провайдер | Доступ | Base URL |
|---|---|---|
| DeepSeek (аккаунт) | вход на chat.deepseek.com | `https://chat.deepseek.com` |
| Gemini (аккаунт) | вход в Google на gemini.google.com | `https://gemini.google.com` |
| OpenRouter | API-ключ openrouter.ai → Keys | `https://openrouter.ai/api/v1` |
| AnyModel | API-ключ anymodel.org → кабинет | `https://anymodel.org/v1` |
| DeepSeek API | API-ключ platform.deepseek.com | `https://api.deepseek.com/v1` |
| Gemini API | API-ключ aistudio.google.com/apikey | `https://generativelanguage.googleapis.com` |
| Gemini через релей | тот же ключ Google | адрес вашего Worker |

Названия моделей у провайдеров меняются. Если модель не найдена —
введите её вручную: «Провайдер и модель» → «Своя модель…».

## Вход в аккаунт DeepSeek и Gemini

Пароль вводится только на настоящем сайте провайдера внутри встроенного
браузера. Приложение не видит и не хранит его.

- **DeepSeek.** После входа UniChat забирает токен сессии из `localStorage`
  и обращается к тем же endpoint'ам, что и сайт: создание чата, proof-of-work
  (`DeepSeekHashV1`, официальный WASM-модуль) и streaming completion.
- **Gemini.** Запрос `StreamGenerate` выполняется XHR-ом внутри залогиненного
  WKWebView на домене `gemini.google.com`. Cookie, включая HttpOnly, отправляет
  сам WebKit, поэтому не нужен ручной разбор сессии Google.
- **Сброс.** На экране входа кнопка «Сброс» удаляет cookie сайта и сохранённый
  токен.
- **Google и встроенный браузер.** Google иногда блокирует вход в WKWebView
  («browser may not be secure»). В этом случае используйте Gemini API по ключу
  или релей.

Это неофициальный клиент к веб-версиям. Используйте на свой риск и соблюдайте
условия провайдера.

### Бесплатный доступ

- **DeepSeek (аккаунт)** — бесплатный веб-чат DeepSeek.
- **Gemini (аккаунт)** — бесплатный тариф обычного аккаунта Google.
- **Gemini API** — бесплатный тариф в Google AI Studio (лимиты по запросам).
- **OpenRouter** — модели с суффиксом `:free`.
- **DeepSeek API** — платный, но дешёвый; при регистрации бывают бонусные кредиты.
- **AnyModel** — оплата по токенам, один ключ на GPT/Claude/Gemini/DeepSeek.

### Gemini в РФ

Прямой домен Google может быть недоступен. Варианты:

1. **Вход в аккаунт Gemini.** Если `gemini.google.com` открывается на
   устройстве, используйте провайдера «Gemini (аккаунт)».
2. **Свой релей (для API-ключа).** Разверните `Relay/gemini-relay.js` как
   Cloudflare Worker (инструкция внутри файла), затем укажите его адрес в Base
   URL провайдера Gemini. Ключ остаётся ключом Google, релей не хранит данные.
   Для дополнительной защиты задайте `RELAY_SECRET` и добавьте заголовок
   `x-relay-secret` в «Доп. заголовки».
3. **Через OpenRouter/AnyModel** — у них есть модели Gemini, доступные
   без прямого подключения к Google.

Учитывайте, что доступ из неподдерживаемых регионов может нарушать условия
провайдера. Ответственность за использование — на вас.

## Архитектура

```
UniChat/
├── UniChat.xcodeproj
├── Relay/gemini-relay.js        # опциональный прокси для Gemini
└── UniChat/
    ├── AppDelegate.swift
    ├── Info.plist
    ├── Core/
    │   ├── Models.swift          # ChatMessage, Conversation
    │   ├── Store.swift           # JSON-хранилище чатов
    │   ├── Keychain.swift        # API-ключи и токены аккаунтов
    │   ├── Settings.swift        # ProviderConfig, AppSettings
    │   ├── HTTP.swift            # SSE-парсер, ошибки
    │   ├── Markdown.swift        # Markdown → NSAttributedString
    │   ├── WebSupport.swift      # общий WKWebView, Safari UA, cookie
    │   └── Theme.swift           # цвета, шрифты, форматирование
    ├── Providers/
    │   ├── ChatProvider.swift    # протокол + тест подключения
    │   ├── OpenAICompatibleProvider.swift
    │   ├── GeminiProvider.swift
    │   ├── DeepSeekPoW.swift     # DeepSeekHashV1 на WASM
    │   ├── DeepSeekAccountProvider.swift
    │   ├── GeminiWebSession.swift
    │   ├── GeminiAccountProvider.swift
    │   └── ProviderFactory.swift
    ├── Resources/
    │   └── deepseek_pow.wasm     # официальный PoW-модуль DeepSeek
    └── UI/
        ├── ConversationsViewController.swift
        ├── ChatViewController.swift
        ├── MessageCell.swift
        ├── ComposerView.swift
        ├── SettingsViewController.swift
        ├── ProviderEditorViewController.swift
        ├── AccountLoginViewController.swift
        └── InfoViewController.swift
```

### Как добавить свой провайдер

Если API OpenAI-совместимый — ничего кодить не нужно:
«Настройки» → «Добавить провайдера» → указать Base URL, модель, ключ.

Если протокол другой — реализуйте `ChatProvider` и добавьте кейс в
`ProviderKind` + `ProviderFactory`.

## Особенности iOS 12

- UIKit only: без SwiftUI, Combine и async/await.
- Без SF Symbols (появились в iOS 13) — текстовые иконки.
- Стриминг через `URLSessionDataDelegate`, а не `URLSessionWebSocketTask`.
- Аккаунты — через `WKWebView`; cookie хранит `WKWebsiteDataStore`.
- `NSAllowsArbitraryLoads = true` — чтобы можно было подключать локальные
  шлюзы по HTTP. Для App Store это стоит заменить на исключения по доменам.

## Ограничения

- Нет иконки приложения и launch-ассетов — добавьте `Assets.xcassets`
  перед публикацией в App Store.
- Нет синхронизации между устройствами.
- Один системный промпт на провайдера; отдельного промпта на чат нет.
- Reasoning-контент DeepSeek показывается блоком «Размышления» в режиме
  аккаунта; в API-режиме выводится только финальный ответ.
- Google может блокировать вход во встроенном браузере; это ограничение
  Google, а не приложения.

