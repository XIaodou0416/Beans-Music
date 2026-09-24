import SwiftUI
import UIKit

enum AppManualFontSize: Int, CaseIterable, Identifiable {
    case extraSmall
    case small
    case medium
    case standard
    case large
    case extraLarge
    case extraExtraLarge
    case accessibility

    static let defaultValue: AppManualFontSize = .standard

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .extraSmall: return "最小"
        case .small: return "较小"
        case .medium: return "小"
        case .standard: return "标准"
        case .large: return "大"
        case .extraLarge: return "较大"
        case .extraExtraLarge: return "特大"
        case .accessibility: return "辅助大字"
        }
    }

    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .extraSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .standard: return .large
        case .large: return .extraLarge
        case .extraLarge: return .extraExtraLarge
        case .extraExtraLarge: return .extraExtraExtraLarge
        case .accessibility: return .accessibilityMedium
        }
    }
}

enum AppTypography {
    enum Role: String, Hashable {
        case pageTitle
        case navigationTitle
        case sectionTitle
        case videoDetailTitle
        case feedVideoTitle
        case compactVideoTitle
        case dynamicBody
        case author
        case compactAuthor
        case commentAuthor
        case commentBody
        case metadata
        case tertiaryMetadata
        case action
        case badge
        case liveRoomTitle
        case liveChatName
        case liveChatBody
        case messageName
        case messagePreview
        case messageBody
        case settingsRow
        case settingsSubtitle
        case diagnostic

        var pointSize: CGFloat {
            switch self {
            case .pageTitle:
                return 34
            case .navigationTitle, .sectionTitle, .videoDetailTitle, .dynamicBody, .messageBody:
                return 17
            case .liveRoomTitle, .messageName, .settingsRow:
                return 16
            case .feedVideoTitle, .author, .commentBody:
                return 15
            case .compactVideoTitle, .commentAuthor, .liveChatBody, .messagePreview:
                return 14
            case .liveChatName, .settingsSubtitle:
                return 13
            case .compactAuthor, .metadata, .action, .diagnostic:
                return 12
            case .tertiaryMetadata, .badge:
                return 11
            }
        }

        var design: Design {
            self == .diagnostic ? .monospaced : .default
        }

        var nativeTextStyle: Font.TextStyle {
            switch self {
            case .pageTitle:
                return .largeTitle
            case .videoDetailTitle:
                return .title3
            case .navigationTitle, .sectionTitle, .feedVideoTitle, .liveRoomTitle, .messageName:
                return .headline
            case .compactVideoTitle, .commentAuthor, .liveChatBody, .messagePreview:
                return .subheadline
            case .dynamicBody, .commentBody, .messageBody, .settingsRow:
                return .body
            case .author:
                return .subheadline
            case .compactAuthor, .liveChatName:
                return .footnote
            case .metadata, .settingsSubtitle:
                return .footnote
            case .action:
                return .subheadline
            case .tertiaryMetadata:
                return .caption
            case .badge:
                return .caption2
            case .diagnostic:
                return .caption
            }
        }

        var nativeUITextStyle: UIFont.TextStyle {
            switch self {
            case .pageTitle:
                return .largeTitle
            case .videoDetailTitle:
                return .title3
            case .navigationTitle, .sectionTitle, .feedVideoTitle, .liveRoomTitle, .messageName:
                return .headline
            case .compactVideoTitle, .commentAuthor, .liveChatBody, .messagePreview:
                return .subheadline
            case .dynamicBody, .commentBody, .messageBody, .settingsRow:
                return .body
            case .author:
                return .subheadline
            case .compactAuthor, .liveChatName:
                return .footnote
            case .metadata, .settingsSubtitle:
                return .footnote
            case .action:
                return .subheadline
            case .tertiaryMetadata:
                return .caption1
            case .badge:
                return .caption2
            case .diagnostic:
                return .caption1
            }
        }

        var nativeWeight: Weight? {
            switch self {
            case .pageTitle:
                return .bold
            case .videoDetailTitle, .compactVideoTitle, .commentAuthor, .badge:
                return .semibold
            case .liveChatName:
                return .medium
            default:
                return nil
            }
        }

        func nativeFont() -> Font {
            if let nativeWeight {
                return .system(
                    nativeTextStyle,
                    design: design.swiftUIDesign,
                    weight: nativeWeight.swiftUIWeight
                )
            }
            return .system(nativeTextStyle, design: design.swiftUIDesign)
        }

        func uiFont(contentSizeCategory: UIContentSizeCategory) -> UIFont {
            let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
            let preferredFont = UIFont.preferredFont(
                forTextStyle: nativeUITextStyle,
                compatibleWith: traits
            )
            let weightedFont = nativeWeight.map {
                UIFont.systemFont(ofSize: preferredFont.pointSize, weight: $0.uiKitWeight)
            } ?? preferredFont
            guard let design = design.uiKitDesign,
                  let descriptor = weightedFont.fontDescriptor.withDesign(design)
            else {
                return weightedFont
            }
            return UIFont(descriptor: descriptor, size: preferredFont.pointSize)
        }

    }

    enum Weight: Equatable {
        case regular
        case medium
        case semibold
        case bold

        var swiftUIWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }

        var uiKitWeight: UIFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    enum Design {
        case `default`
        case monospaced

        var swiftUIDesign: Font.Design {
            switch self {
            case .default: return .default
            case .monospaced: return .monospaced
            }
        }

        var uiKitDesign: UIFontDescriptor.SystemDesign? {
            switch self {
            case .default: return nil
            case .monospaced: return .monospaced
            }
        }
    }

}

private struct AppTypographyModifier: ViewModifier {
    let role: AppTypography.Role

    func body(content: Content) -> some View {
        content.font(role.nativeFont())
    }
}

extension View {
    func appTypography(_ role: AppTypography.Role, fallback _: Font) -> some View {
        modifier(AppTypographyModifier(role: role))
    }

    func appTypography(_ role: AppTypography.Role) -> some View {
        modifier(AppTypographyModifier(role: role))
    }

}

extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        default: return .large
        }
    }
}

enum FeedTypography {
    static let primaryTextSize: CGFloat = 15
    static let bodyLineSpacing: CGFloat = 2

    static let bodyFont: Font = .system(size: primaryTextSize, weight: .regular)
    static let titleFont: Font = .system(size: primaryTextSize, weight: .semibold)

    static let bodyUIFont = UIFont.systemFont(ofSize: primaryTextSize, weight: .regular)
    static let titleUIFont = UIFont.systemFont(ofSize: primaryTextSize, weight: .semibold)
}
