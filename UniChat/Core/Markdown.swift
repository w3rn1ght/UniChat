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
                .backgroundColor: UIColor(white: 0.45, alpha: 0.13)
            ], range: inner)
            attributed.deleteCharacters(in: NSRange(location: range.location + range.length - 1, length: 1))
            attributed.deleteCharacters(in: NSRange(location: range.location, length: 1))
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
