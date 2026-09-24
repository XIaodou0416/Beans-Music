import SwiftUI
import UIKit

struct DynamicAttributedTextInput: Equatable {
    let segments: [DynamicTextSegment]
    let baseFont: UIFont
    let textColor: UIColor
    let emoteSize: CGFloat
    let maxLines: Int?
    let typographyRole: AppTypography.Role?
    let lineHeightMultiplier: CGFloat
    static let feedBodyFont = FeedTypography.bodyUIFont

    init(
        segments: [DynamicTextSegment],
        baseFont: UIFont,
        textColor: UIColor,
        emoteSize: CGFloat,
        maxLines: Int?,
        typographyRole: AppTypography.Role?,
        lineHeightMultiplier: CGFloat = 1
    ) {
        self.segments = segments
        self.baseFont = baseFont
        self.textColor = textColor
        self.emoteSize = emoteSize
        self.maxLines = maxLines
        self.typographyRole = typographyRole
        self.lineHeightMultiplier = lineHeightMultiplier
    }

    static func dynamicFeedBody(
        segments: [DynamicTextSegment],
        emoteSize: CGFloat,
        maxLines: Int?
    ) -> DynamicAttributedTextInput {
        DynamicAttributedTextInput(
            segments: segments.isEmpty ? [.text(" ")] : segments,
            baseFont: Self.feedBodyFont,
            textColor: .label,
            emoteSize: emoteSize,
            maxLines: maxLines,
            typographyRole: .dynamicBody,
            lineHeightMultiplier: 1
        )
    }

    static func == (lhs: DynamicAttributedTextInput, rhs: DynamicAttributedTextInput) -> Bool {
        lhs.segments == rhs.segments
            && lhs.baseFont.fontName == rhs.baseFont.fontName
            && lhs.baseFont.pointSize == rhs.baseFont.pointSize
            && lhs.textColor == rhs.textColor
            && lhs.emoteSize == rhs.emoteSize
            && lhs.maxLines == rhs.maxLines
            && lhs.typographyRole == rhs.typographyRole
            && lhs.lineHeightMultiplier == rhs.lineHeightMultiplier
    }

    var cacheKey: String {
        let segmentKey = segments
            .map { segment -> String in
                switch segment {
                case .text(let text):
                    return "t:\(text)"
                case .emoji(let text, let url):
                    return "e:\(text):\(url ?? "")"
                case .link(let text, let url):
                    return "l:\(text):\(url)"
                case .mention(let text, let mid, let url):
                    return "m:\(text):\(mid.map(String.init) ?? ""):\(url ?? "")"
                }
            }
            .joined(separator: "\u{1f}")
        return [
            segmentKey,
            baseFont.fontName,
            "\(baseFont.pointSize)",
            "\(textColor.dynamicRGBAKey)",
            "\(emoteSize)",
            "\(maxLines ?? -1)",
            typographyRole?.rawValue ?? "",
            "\(lineHeightMultiplier)"
        ].joined(separator: "\u{1e}")
    }

    func resolvingTypography(contentSizeCategory: UIContentSizeCategory) -> DynamicAttributedTextInput {
        guard let typographyRole else { return self }

        let resolvedFont = typographyRole.uiFont(contentSizeCategory: contentSizeCategory)
        return DynamicAttributedTextInput(
            segments: segments,
            baseFont: resolvedFont,
            textColor: textColor,
            emoteSize: emoteSize * resolvedFont.pointSize / typographyRole.pointSize,
            maxLines: maxLines,
            typographyRole: typographyRole,
            lineHeightMultiplier: lineHeightMultiplier
        )
    }

    func replacingLineHeightMultiplier(_ multiplier: CGFloat) -> DynamicAttributedTextInput {
        DynamicAttributedTextInput(
            segments: segments,
            baseFont: baseFont,
            textColor: textColor,
            emoteSize: emoteSize,
            maxLines: maxLines,
            typographyRole: typographyRole,
            lineHeightMultiplier: multiplier
        )
    }

    var nativePlainText: String? {
        var text = ""
        for segment in segments {
            guard case .text(let value) = segment else { return nil }
            text += value
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func nativeSwiftUIFont() -> Font {
        if let typographyRole {
            return typographyRole.nativeFont()
        }
        return .system(size: baseFont.pointSize, weight: baseFont.feedFontWeight)
    }

    func nativeAttributedPlainText(_ text: String) -> AttributedString {
        DynamicTextLineBreakStyle.attributedString(
            for: text,
            lineLimit: maxLines,
            lineSpacing: additionalLineSpacing
        )
    }

    func exceedsMaximumLineCount(fittingWidth width: CGFloat) -> Bool {
        guard let maxLines, maxLines > 0, width.isFinite, width > 1 else { return false }

        let textStorage = NSTextStorage(attributedString: render().attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = lineBreakMode
        textContainer.maximumNumberOfLines = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var lineCount = 0
        var glyphIndex = glyphRange.location
        let glyphRangeEnd = NSMaxRange(glyphRange)

        while glyphIndex < glyphRangeEnd {
            var lineRange = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            guard lineRange.length > 0 else { break }

            lineCount += 1
            if lineCount > maxLines {
                return true
            }
            glyphIndex = NSMaxRange(lineRange)
        }

        return false
    }

    func render() -> (attributedString: NSAttributedString, missingImageURLs: [URL]) {
        let result = NSMutableAttributedString()
        var missingImageURLs = [URL]()

        for segment in segments {
            switch segment {
            case .text(let text):
                result.append(attributedText(text))
            case .emoji(let text, let url):
                result.append(emoteAttachment(for: text, urlString: url, missingImageURLs: &missingImageURLs))
            case .link(let title, let rawURL):
                if let normalized = AppLinkRouter.normalizedHTTPURLString(rawURL),
                   let url = URL(string: normalized) {
                    result.append(BiliMentionTextRenderer.linkAttributedString(title: title, url: url, font: baseFont))
                } else {
                    result.append(attributedText(title))
                }
            case .mention(let text, let mid, let url):
                let mention = BiliMention(text: text, mid: mid, url: url)
                result.append(
                    BiliMentionTextRenderer.attributedString(
                        for: text,
                        baseColor: textColor,
                        font: baseFont,
                        mentions: [mention].compactMap { $0 }
                    )
                )
            }
        }

        if result.length == 0 {
            result.append(attributedText(" "))
        }

        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
        return (result, Array(Set(missingImageURLs)))
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        if lineHeightMultiplier > 0, lineHeightMultiplier != 1 {
            let lineHeight = baseFont.lineHeight * lineHeightMultiplier
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        }
        style.lineBreakMode = lineBreakMode
        style.lineBreakStrategy = lineBreakStrategy
        return style
    }

    private var additionalLineSpacing: CGFloat {
        guard lineHeightMultiplier > 1 else { return 0 }
        return baseFont.lineHeight * (lineHeightMultiplier - 1)
    }

    var lineBreakMode: NSLineBreakMode {
        plainTextForLineBreaking.prefersCharacterWrappingForCJKText ? .byCharWrapping : .byWordWrapping
    }

    var lineBreakStrategy: NSParagraphStyle.LineBreakStrategy {
        plainTextForLineBreaking.prefersCharacterWrappingForCJKText ? [] : .standard
    }

    private var plainTextForLineBreaking: String {
        segments
            .map { segment -> String in
                switch segment {
                case .text(let text):
                    text
                case .emoji(let text, _):
                    text
                case .link(let title, _):
                    title
                case .mention(let text, _, _):
                    text
                }
            }
            .joined()
    }

    private func attributedText(_ text: String) -> NSAttributedString {
        BiliMentionTextRenderer.attributedString(
            for: text,
            baseColor: textColor,
            font: baseFont,
            mentions: []
        )
    }

    private func emoteAttachment(for token: String, urlString: String?, missingImageURLs: inout [URL]) -> NSAttributedString {
        guard let urlString, let url = URL(string: urlString) else {
            return attributedText(token)
        }

        let attachment = NSTextAttachment()
        if let image = BiliEmoteImageStore.shared.cachedImage(for: url) {
            attachment.image = image
        } else {
            attachment.image = BiliEmoteImageStore.shared.placeholderImage(size: emoteSize)
            missingImageURLs.append(url)
        }
        attachment.bounds = CGRect(
            x: 0,
            y: (baseFont.capHeight - emoteSize) / 2,
            width: emoteSize,
            height: emoteSize
        )
        return NSAttributedString(attachment: attachment)
    }
}

private extension UIColor {
    var dynamicRGBAKey: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "\(red),\(green),\(blue),\(alpha)"
    }
}

private extension UIFont {
    var feedFontWeight: Font.Weight {
        fontDescriptor.symbolicTraits.contains(.traitBold) ? .semibold : .regular
    }
}
