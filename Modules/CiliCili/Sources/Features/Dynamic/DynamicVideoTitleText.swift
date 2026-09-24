import SwiftUI

struct DynamicVideoTitleText: View {
    enum Style {
        case feed
        case compact

        var font: Font {
            switch self {
            case .feed:
                FeedTypography.titleFont
            case .compact:
                FeedTypography.titleFont
            }
        }

        var typographyRole: AppTypography.Role {
            switch self {
            case .feed:
                return .feedVideoTitle
            case .compact:
                return .compactVideoTitle
            }
        }
    }

    let title: String
    let style: Style
    let lineLimit: Int

    init(_ title: String, style: Style, lineLimit: Int = 2) {
        self.title = title
        self.style = style
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(attributedTitle)
            .appTypography(style.typographyRole)
            .foregroundStyle(.primary)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .allowsTightening(true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .accessibilityLabel(title)
    }

    private var attributedTitle: AttributedString {
        DynamicTextLineBreakStyle.attributedString(
            for: title,
            lineLimit: lineLimit
        )
    }
}
