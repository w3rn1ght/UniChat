import UIKit

/// Мини-рендер Markdown в NSAttributedString (без внешних зависимостей).
enum Markdown {

    static func render(_ text: String,
                       color: UIColor = Theme.primaryText,
                       font: UIFont = Theme.bodyFont) -> NSAttributedString {

        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")

        var index = 0
        var inCodeBlock = false
        var codeLines: [String] = []
        var lastWasBlank = false

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    appendCodeBlock(codeLines.joined(separator: "\n"), to: result, color: color)
                    codeLines.removeAll()
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                index += 1
                lastWasBlank = false
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                if !lastWasBlank {
                    result.append(NSAttributedString(string: "\n",
                                                     attributes: baseAttributes(color: color, font: font)))
                    lastWasBlank = true
                }
                index += 1
                continue
            }
            lastWasBlank = false

            if trimmed.hasPrefix("#") {
                var title = trimmed
                while title.hasPrefix("#") { title.removeFirst() }
                title = title.trimmingCharacters(in: .whitespaces)
                let titleFont = UIFont.boldSystemFont(ofSize: max(font.pointSize + 1.5, 16))
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacing = 3
                paragraph.lineSpacing = 2
                let attributed = NSMutableAttributedString(string: title + "\n", attributes: [
                    .font: titleFont,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ])
                applyInline(to: attributed, baseFont: titleFont, color: color)
                result.append(attributed)
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                result.append(NSAttributedString(string: "──────────\n", attributes: [
                    .font: font,
                    .foregroundColor: Theme.separator
                ]))
                index += 1
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let content = String(trimmed.dropFirst(2))
                result.append(inlineAttributed("• " + content + "\n", color: color, font: font))
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") {
                let content = String(trimmed.dropFirst(2))
                let quoteFont = italic(font)
                result.append(inlineAttributed(content + "\n",
                                               color: Theme.secondaryText,
                                               font: quoteFont))
                index += 1
                continue
            }

            result.append(inlineAttributed(line + "\n", color: color, font: font))
            index += 1
        }

        if inCodeBlock && !codeLines.isEmpty {
            appendCodeBlock(codeLines.joined(separator: "\n"), to: result, color: color)
        }

        if result.length > 0 && result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return result
    }

    // MARK: - Блоки

    private static func baseAttributes(color: UIColor, font: UIFont) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 2
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private static func inlineAttributed(_ string: String,
                                         color: UIColor,
                                         font: UIFont) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: string,
                                                   attributes: baseAttributes(color: color, font: font))
        applyInline(to: attributed, baseFont: font, color: color)
        return attributed
    }

    private static func appendCodeBlock(_ code: String,
                                        to result: NSMutableAttributedString,
                                        color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 6
        paragraph.firstLineHeadIndent = 6
        paragraph.tailIndent = -6
        paragraph.paragraphSpacing = 6
        paragraph.lineSpacing = 1

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.monoFont,
            .foregroundColor: color,
            .backgroundColor: UIColor(white: 0.45, alpha: 0.13),
            .paragraphStyle: paragraph
        ]
        result.append(NSAttributedString(string: code + "\n", attributes: attributes))
    }

    // MARK: - Инлайн-разметка

    private static func applyInline(to attributed: NSMutableAttributedString,
                                    baseFont: UIFont,
                                    color: UIColor) {

        // `код`
        applyPattern("`([^`\\n]+)`", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 2 else { return }
            let inner = NSRange(location: range.location + 1, length: range.length - 2)
            attributed.addAttributes([
                .font: Theme.monoFont,
                .backgroundColor: Theme.surfaceContainerHigh
            ], range: inner)
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 1, length: 1))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 1))
        }

        // LaTeX-формулы: $$...$$ и $...$. Модели часто присылают их вместо
        // обычного текста; убираем разделители и переводим частые команды
        // в Unicode, чтобы формулы не выглядели как сырой код.
        applyPattern("\\$\\$([^$\\n]+?)\\$\\$", to: attributed) { match, original in
            replaceLaTeX(match.range, in: attributed, original: original, wrappers: 2)
        }
        applyPattern("(?<!\\$)\\$([^$\\n]+?)\\$(?!\\$)", to: attributed) { match, original in
            replaceLaTeX(match.range, in: attributed, original: original, wrappers: 1)
        }

        // [текст](ссылка)
        applyPattern("\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)", to: attributed) { match, original in
            let label = original.substring(with: match.range(at: 1))
            let urlString = original.substring(with: match.range(at: 2))
            attributed.replaceCharacters(in: match.range, with: label)
            let range = NSRange(location: match.range.location, length: (label as NSString).length)
            attributed.addAttributes([
                .foregroundColor: Theme.accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: urlString
            ], range: range)
        }

        // **жирный**
        applyPattern("\\*\\*([^*\\n]+)\\*\\*", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 4 else { return }
            attributed.addAttribute(.font,
                                    value: bold(baseFont),
                                    range: NSRange(location: range.location + 2, length: range.length - 4))
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 2, length: 2))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 2))
        }

        // __жирный__
        applyPattern("__([^_\\n]+)__", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 4 else { return }
            attributed.addAttribute(.font,
                                    value: bold(baseFont),
                                    range: NSRange(location: range.location + 2, length: range.length - 4))
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 2, length: 2))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 2))
        }

        // ~~зачёркнутый~~
        applyPattern("~~([^~\\n]+)~~", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 4 else { return }
            attributed.addAttribute(.strikethroughStyle,
                                    value: NSUnderlineStyle.single.rawValue,
                                    range: NSRange(location: range.location + 2, length: range.length - 4))
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 2, length: 2))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 2))
        }

        // *курсив*
        applyPattern("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 2 else { return }
            attributed.addAttribute(.font,
                                    value: italic(baseFont),
                                    range: NSRange(location: range.location + 1, length: range.length - 2))
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 1, length: 1))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 1))
        }

        // _курсив_
        applyPattern("(?<!_)_([^_\\n]+)_(?!_)", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 2 else { return }
            attributed.addAttribute(.font,
                                    value: italic(baseFont),
                                    range: NSRange(location: range.location + 1, length: range.length - 2))
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 1, length: 1))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 1))
        }

        // ++подчёркнутый++ — одна черта (например, подлежащее).
        applyPattern("\\+\\+([^+\\n]+?)\\+\\+", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 4 else { return }
            attributed.addAttribute(.underlineStyle,
                                    value: NSUnderlineStyle.single.rawValue,
                                    range: NSRange(location: range.location + 2, length: range.length - 4))
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 2, length: 2))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 2))
        }

        // ==текст== — двойная черта (сказуемое и другие разборы).
        applyPattern("==([^=\\n]+?)==", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 4 else { return }
            attributed.addAttribute(.underlineStyle,
                                    value: NSUnderlineStyle.double.rawValue,
                                    range: NSRange(location: range.location + 2, length: range.length - 4))
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 2, length: 2))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 2))
        }

        // HTML-подчёркивание <u>...</u> — его иногда присылают модели.
        applyPattern("<u>([^<\\n]+?)</u>", to: attributed) { match, _ in
            let range = match.range
            guard range.length > 7 else { return }
            attributed.addAttribute(.underlineStyle,
                                    value: NSUnderlineStyle.single.rawValue,
                                    range: NSRange(location: range.location + 3, length: range.length - 7))
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 4, length: 4))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 3))
        }
    }

    /// Убирает $...$ / $$...$$ и переводит простые LaTeX-команды в Unicode.
    private static func replaceLaTeX(_ range: NSRange,
                                     in attributed: NSMutableAttributedString,
                                     original: NSString,
                                     wrappers: Int) {
        let innerLength = range.length - wrappers * 2
        guard innerLength > 0 else { return }
        let inner = original.substring(with: NSRange(location: range.location + wrappers,
                                                     length: innerLength))
        if wrappers == 1 {
            let mathCharacters = CharacterSet(charactersIn: "\\^_=+-*/×÷±≤≥≠≈∞√")
            let looksLikeNumber = Double(inner.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            if inner.rangeOfCharacter(from: mathCharacters) == nil && !looksLikeNumber {
                return
            }
        }
        let converted = latexToUnicode(inner)
        attributed.replaceCharacters(in: range, with: converted)
        let newRange = NSRange(location: range.location, length: (converted as NSString).length)
        if newRange.length > 0 {
            attributed.addAttribute(.font, value: Theme.monoFont, range: newRange)
        }
    }

    private static func latexToUnicode(_ text: String) -> String {
        var value = text
        let replacements: [(String, String)] = [
            ("\\\\frac", " "), ("\\\\cdot", "·"), ("\\\\times", "×"),
            ("\\\\div", "÷"), ("\\\\pm", "±"), ("\\\\le", "≤"),
            ("\\\\ge", "≥"), ("\\\\neq", "≠"), ("\\\\approx", "≈"),
            ("\\\\infty", "∞"), ("\\\\sqrt", "√"), ("\\\\pi", "π"),
            ("\\\\alpha", "α"), ("\\\\beta", "β"), ("\\\\gamma", "γ"),
            ("\\\\Delta", "Δ"), ("\\\\sum", "Σ"), ("\\\\int", "∫"),
            ("\\\\angle", "∠"), ("\\\\triangle", "△"), ("\\\\parallel", "∥"),
            ("\\\\perp", "⊥"), ("\\\\degree", "°"), ("\\\\%", "%"),
            ("\\\\left", ""), ("\\\\right", ""), ("\\\\,", " "),
            ("\\\\;", " "), ("\\\\!", ""), ("\\\\ ", " ")
        ]
        for (from, to) in replacements {
            value = value.replacingOccurrences(of: from, with: to)
        }
        value = value.replacingOccurrences(of: "\\{", with: "")
            .replacingOccurrences(of: "\\}", with: "")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        value = value.replacingOccurrences(of: "\\^", with: "^")
            .replacingOccurrences(of: "\\_", with: "_")
        // x^2 -> x², x_1 -> x₁ (только цифры и знаки).
        value = replaceScript(value, marker: "^", superscript: true)
        value = replaceScript(value, marker: "_", superscript: false)
        return value.replacingOccurrences(of: "$", with: "")
    }

    private static func replaceScript(_ text: String, marker: Character, superscript: Bool) -> String {
        let supers: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
            "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ"
        ]
        let subs: [Character: Character] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"
        ]
        let map = superscript ? supers : subs
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == marker {
                let next = text.index(after: index)
                if next < text.endIndex, let mapped = map[text[next]] {
                    result.append(mapped)
                    index = text.index(after: next)
                    continue
                }
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result
    }

    private static func applyPattern(_ pattern: String,
                                     to attributed: NSMutableAttributedString,
                                     handler: (NSTextCheckingResult, NSString) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let original = attributed.string as NSString
        let fullRange = NSRange(location: 0, length: original.length)
        let matches = regex.matches(in: attributed.string, options: [], range: fullRange)

        for match in matches.reversed() {
            guard match.range.location != NSNotFound else { continue }
            handler(match, original)
        }
    }

    // MARK: - Шрифты

    private static func bold(_ font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor
        if let boldDescriptor = descriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: boldDescriptor, size: font.pointSize)
        }
        return UIFont.boldSystemFont(ofSize: font.pointSize)
    }

    private static func italic(_ font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor
        if let italicDescriptor = descriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: italicDescriptor, size: font.pointSize)
        }
        return UIFont.italicSystemFont(ofSize: font.pointSize)
    }
}
