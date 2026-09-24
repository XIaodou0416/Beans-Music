import SwiftUI
import UIKit

struct StableVideoTitleText: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum Style {
        case feedStory
        case feedHeadline
        case compactCard
        case related

        var typographyRole: AppTypography.Role {
            switch self {
            case .feedStory, .feedHeadline:
                return .feedVideoTitle
            case .compactCard, .related:
                return .compactVideoTitle
            }
        }

        var uiFont: UIFont {
            switch self {
            case .feedStory:
                return FeedTypography.titleUIFont
            case .feedHeadline:
                return FeedTypography.titleUIFont
            case .compactCard:
                return UIFontMetrics(forTextStyle: .subheadline)
                    .scaledFont(for: .systemFont(ofSize: 14.5, weight: .semibold))
            case .related:
                return UIFontMetrics(forTextStyle: .subheadline)
                    .scaledFont(for: .systemFont(ofSize: 14.5, weight: .semibold))
            }
        }
    }

    let title: String
    let style: Style
    let lineLimit: Int
    let preferredWidth: CGFloat?

    init(
        _ title: String,
        style: Style,
        lineLimit: Int = 2,
        preferredWidth: CGFloat? = nil
    ) {
        self.title = title
        self.style = style
        self.lineLimit = lineLimit
        self.preferredWidth = preferredWidth
    }

    var body: some View {
        StableVideoTitleLabel(
            title: title,
            font: resolvedFont,
            lineLimit: lineLimit,
            preferredWidth: preferredWidth,
            adjustsFontForContentSizeCategory: true,
            allowsNaturalHeight: true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(title)
    }

    private var resolvedFont: UIFont {
        style.typographyRole.uiFont(contentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
    }
}

private struct StableVideoTitleLabel: UIViewRepresentable {
    let title: String
    let font: UIFont
    let lineLimit: Int
    let preferredWidth: CGFloat?
    let adjustsFontForContentSizeCategory: Bool
    let allowsNaturalHeight: Bool

    final class Coordinator {
        var lastSignature: Signature?
        var lastMeasuredWidth: CGFloat?

        func measuredWidth(proposedWidth: CGFloat?, preferredWidth: CGFloat?, boundsWidth: CGFloat) -> CGFloat? {
            let preferred = validWidth(preferredWidth)
            let proposed = validWidth(proposedWidth)

            if let preferred {
                return ceil(max(preferred, proposed ?? 0))
            }

            if let proposed {
                return ceil(proposed)
            }

            if boundsWidth.isFinite, boundsWidth > 1 {
                return ceil(boundsWidth)
            }

            if let lastMeasuredWidth, lastMeasuredWidth.isFinite, lastMeasuredWidth > 1 {
                return ceil(lastMeasuredWidth)
            }

            return nil
        }

        private func validWidth(_ width: CGFloat?) -> CGFloat? {
            guard let width, width.isFinite, width > 1 else { return nil }
            return width
        }
    }

    struct Signature: Equatable {
        let title: String
        let fontName: String
        let pointSize: CGFloat
        let lineLimit: Int
        let preferredWidth: CGFloat?
        let adjustsFontForContentSizeCategory: Bool
        let allowsNaturalHeight: Bool
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = lineLimit
        label.lineBreakMode = titleLineBreakMode
        if #available(iOS 14.0, *) {
            label.lineBreakStrategy = titleLineBreakStrategy
        }
        label.adjustsFontForContentSizeCategory = adjustsFontForContentSizeCategory
        label.allowsDefaultTighteningForTruncation = true
        label.textAlignment = .natural
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let signature = Signature(
            title: title,
            fontName: font.fontName,
            pointSize: font.pointSize,
            lineLimit: lineLimit,
            preferredWidth: preferredWidth,
            adjustsFontForContentSizeCategory: adjustsFontForContentSizeCategory,
            allowsNaturalHeight: allowsNaturalHeight
        )
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature

        label.numberOfLines = lineLimit
        label.lineBreakMode = titleLineBreakMode
        if #available(iOS 14.0, *) {
            label.lineBreakStrategy = titleLineBreakStrategy
        }
        label.adjustsFontForContentSizeCategory = adjustsFontForContentSizeCategory
        label.attributedText = attributedTitle
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = context.coordinator.measuredWidth(
            proposedWidth: proposal.width,
            preferredWidth: preferredWidth,
            boundsWidth: uiView.bounds.width
        ) else {
            context.coordinator.lastMeasuredWidth = nil
            uiView.preferredMaxLayoutWidth = 0
            return nil
        }

        context.coordinator.lastMeasuredWidth = width
        uiView.preferredMaxLayoutWidth = width
        let measured = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let maxHeight = ceil(font.lineHeight * CGFloat(max(lineLimit, 1)) + 2)
        let height = allowsNaturalHeight ? ceil(measured.height) : min(ceil(measured.height), maxHeight)
        return CGSize(width: width, height: height)
    }

    private var attributedTitle: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = titleLineBreakMode
        paragraphStyle.alignment = .natural
        paragraphStyle.hyphenationFactor = 0
        paragraphStyle.lineBreakStrategy = titleLineBreakStrategy
        return NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private var titleLineBreakMode: NSLineBreakMode {
        .byTruncatingTail
    }

    private var titleLineBreakStrategy: NSParagraphStyle.LineBreakStrategy {
        title.prefersCharacterWrappingForCJKText ? [] : .standard
    }
}

extension String {
    var prefersCharacterWrappingForCJKText: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                true
            case 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2B820...0x2CEAF:
                true
            case 0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF:
                true
            default:
                false
            }
        }
    }
}
