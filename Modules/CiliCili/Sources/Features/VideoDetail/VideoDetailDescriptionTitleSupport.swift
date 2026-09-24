import Foundation
import SwiftUI

struct VideoTitleText: View {
    let text: String

    var body: some View {
        Text(text)
            .appTypography(
                .videoDetailTitle,
            )
            .foregroundStyle(.primary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

extension String {
    var normalizedDetailTitle: String {
        var text = self
        ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"].forEach {
            text = text.replacingOccurrences(of: $0, with: "")
        }
        ["\u{2028}", "\u{2029}"].forEach {
            text = text.replacingOccurrences(of: $0, with: " ")
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        text = text.replacingOccurrences(
            of: #"([\p{Han}\p{Hiragana}\p{Katakana}\p{Bopomofo}\p{N}，。！？、：；（）《》“”‘’【】])\s+([\p{Han}\p{Hiragana}\p{Katakana}\p{Bopomofo}\p{N}，。！？、：；（）《》“”‘’【】])"#,
            with: "$1$2",
            options: .regularExpression
        )
        return text
    }
}
