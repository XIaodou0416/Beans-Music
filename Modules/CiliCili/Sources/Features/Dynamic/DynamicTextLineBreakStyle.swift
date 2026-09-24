import Foundation
import UIKit

enum DynamicTextLineBreakStyle {
    static func attributedString(
        for text: String,
        lineLimit: Int?,
        lineSpacing: CGFloat = 0
    ) -> AttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = lineBreakMode(for: text, lineLimit: lineLimit)
        paragraphStyle.alignment = .natural
        paragraphStyle.hyphenationFactor = 0
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakStrategy = lineBreakStrategy(for: text)

        return AttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .paragraphStyle: paragraphStyle
                ]
            )
        )
    }

    static func lineBreakMode(for text: String, lineLimit: Int?) -> NSLineBreakMode {
        guard lineLimit != 1 else { return .byTruncatingTail }
        return text.prefersCharacterWrappingForCJKText ? .byCharWrapping : .byWordWrapping
    }

    static func lineBreakStrategy(for text: String) -> NSParagraphStyle.LineBreakStrategy {
        text.prefersCharacterWrappingForCJKText ? NSParagraphStyle.LineBreakStrategy() : .standard
    }
}
