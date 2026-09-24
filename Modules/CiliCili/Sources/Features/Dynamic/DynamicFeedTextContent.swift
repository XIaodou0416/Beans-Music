import SwiftUI

struct DynamicFeedTextContent: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let collapsedInput: DynamicAttributedTextInput
    let expandedInput: DynamicAttributedTextInput
    let copyText: String?
    let preferredWidth: CGFloat?
    let onOpenDetail: (() -> Void)?
    @Binding var isExpanded: Bool
    @State private var measuredShowsExpandButton: Bool?
    @State private var measuredTextWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DynamicRichTextView(
                input: displayedInput,
                preferredWidth: preferredWidth,
                onNonLinkTap: onOpenDetail,
                usesTextKitLayout: true,
                onContentLayoutChange: { updateExpansionVisibility(fittingWidth: measuredTextWidth) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transaction { transaction in
                transaction.animation = nil
            }
            .dynamicCopyableText(copyText)

            if shouldShowExpandButton {
                Button(action: toggleExpanded) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起" : "展开")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .appTypography(.action, fallback: .footnote.weight(.semibold))
                    .foregroundStyle(appTintColor)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            floor(geometry.size.width)
        } action: { _, viewWidth in
            let textWidth = preferredWidth ?? viewWidth
            measuredTextWidth = textWidth
            updateExpansionVisibility(fittingWidth: textWidth)
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            updateExpansionVisibility(fittingWidth: measuredTextWidth)
        }
        .onChange(of: preferredWidth) { _, _ in
            updateExpansionVisibility(fittingWidth: measuredTextWidth)
        }
        .onChange(of: collapsedInput) { _, _ in
            updateExpansionVisibility(fittingWidth: measuredTextWidth)
        }
    }

    private var displayedInput: DynamicAttributedTextInput {
        let input = isExpanded ? expandedInput : collapsedInput
        return input.replacingLineHeightMultiplier(1.65)
    }

    private var shouldShowExpandButton: Bool { measuredShowsExpandButton == true }

    private func toggleExpanded() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isExpanded.toggle()
        }
    }

    private func updateExpansionVisibility(fittingWidth width: CGFloat) {
        guard width.isFinite, width > 1 else {
            measuredShowsExpandButton = nil
            return
        }

        let input = collapsedInput
            .replacingLineHeightMultiplier(1.65)
            .resolvingTypography(
                contentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
        measuredShowsExpandButton = input.exceedsMaximumLineCount(fittingWidth: width)
    }
}
