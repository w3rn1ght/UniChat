import UIKit

final class InfoViewController: UIViewController {

    enum Topic {
        case keys
        case russia
        case about
    }

    private let topic: Topic

    init(topic: Topic) {
        self.topic = topic
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.background

        switch topic {
        case .keys: title = "Ключи"
        case .russia: title = "Gemini в РФ"
        case .about: title = "О приложении"
        }

        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = Theme.background
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        textView.dataDetectorTypes = .link
        textView.alwaysBounceVertical = true
        textView.attributedText = Markdown.render(content(), color: Theme.primaryText)
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func content() -> String {
        switch topic {
        case .keys:
            return """
            # Ключи и входы

            **Вход в аккаунт (без ключа)**
            В UniChat есть два готовых провайдера: «DeepSeek (аккаунт)» и «Gemini (аккаунт)».
            1. Откройте провайдера и нажмите строку «Аккаунт».
            2. Войдите на настоящем сайте провайдера во встроенном браузере.
            3. Приложение сохранит только сессию: DeepSeek — токен, Gemini — cookie браузера. Пароль нигде не сохраняется.
            Вход можно сбросить кнопкой «Сброс» на экране входа.

            **Google Gemini — API-ключ**
            1. Откройте https://aistudio.google.com/apikey
            2. Создайте ключ (начинается с AIza…).
            3. Вставьте ключ в провайдера «Gemini API».

            **OpenRouter** — есть модели с пометкой «:free».
            1. https://openrouter.ai → Keys → Create key.
            2. Выберите модель с суффиксом «:free».
            3. Вставьте ключ в провайдера «OpenRouter».

            **DeepSeek API**
            1. https://platform.deepseek.com → API keys.
            2. API платный, но очень дешёвый; иногда дают бонусные кредиты.
            Для бесплатного веб-чата используйте режим «DeepSeek (аккаунт)».

            **AnyModel**
            1. https://anymodel.org — один OpenAI-совместимый шлюз к GPT, Claude, Gemini и DeepSeek.
            2. Base URL уже указан: https://anymodel.org/v1
            3. Создайте ключ в кабинете и вставьте в провайдера «AnyModel».

            **Свой шлюз**
            Любой OpenAI-совместимый сервер (включая локальную Ollama) можно добавить кнопкой «Добавить провайдера».
            """

        case .russia:
            return """
            # Gemini в РФ

            Прямой домен Google может быть недоступен. Есть три варианта.

            **Вариант 1. Вход в аккаунт Gemini**
            Если gemini.google.com открывается на этом устройстве, войдите через «Gemini (аккаунт)». Запросы идут внутри встроенного браузера, как на сайте.
            Если Google не пускает встроенный браузер, используйте API-ключ или релей.

            **Вариант 2. Свой релей (для API-ключа)**
            1. Разверните Cloudflare Worker из файла Relay/gemini-relay.js (инструкция внутри файла).
            2. Получите адрес вида https://имя.workers.dev
            3. В настройках провайдера «Gemini API» укажите этот адрес в поле Base URL.
            4. API-ключ остаётся ключом Google AI Studio.

            Релей пропускает только запросы к generativelanguage.googleapis.com и не хранит ключи.

            **Вариант 3. Через OpenRouter или AnyModel**
            У них есть модели Gemini, и они доступны без прямого подключения к Google.
            Выберите провайдера OpenRouter или AnyModel и модель Gemini.

            Учтите: использование сервисов из неподдерживаемых регионов может нарушать их условия. Ответственность за использование лежит на вас.
            """

        default:
            return """
            # UniChat 1.1

            Клиент для iOS 12 и новее. UIKit, без сторонних библиотек.

            • Провайдеры: DeepSeek и Gemini со входом в обычный аккаунт, а также OpenAI-совместимые API (OpenRouter, AnyModel, DeepSeek, свои шлюзы) и Gemini API.
            • Стриминг ответов, Markdown, история чатов.
            • Токены и ключи — в Keychain, cookie аккаунтов — в защищённом хранилище WebKit. История — в Application Support, только на устройстве.
            • Нет аналитики, рекламы и собственного сервера.

            **Как это работает**
            • DeepSeek: вход выполняется на chat.deepseek.com, затем приложение обращается к тем же endpoint'ам, что и сайт, включая proof-of-work.
            • Gemini: запросы выполняются внутри залогиненного WKWebView, поэтому cookie Google отправляет сам WebKit.

            **Ограничения**
            • Это неофициальные клиенты к веб-версиям сервисов. Аккаунт может быть ограничен провайдером; используйте на свой риск.
            • Google может блокировать вход во встроенном браузере. Тогда доступен режим с API-ключом.
            • Названия моделей у провайдеров меняются — модель можно ввести вручную.
            • Для сборки нужен Mac с Xcode. Минимальная цель — iOS 12.0.
            """
        }
    }
}
