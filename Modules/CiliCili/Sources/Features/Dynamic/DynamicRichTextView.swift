import SwiftUI
import UIKit

struct DynamicRichTextView: View {
    let segments: [DynamicTextSegment]
    let font: UIFont
    let textColor: Color
    let emoteSize: CGFloat
    let maxLines: Int?
    let preferredWidth: CGFloat?
    let onNonLinkTap: (() -> Void)?
    let usesTextKitLayout: Bool
    let onContentLayoutChange: (() -> Void)?
    private let textInput: DynamicAttributedTextInput
    @Environment(\.openAppURLAction) private var openAppURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        segments: [DynamicTextSegment],
        font: UIFont,
        textColor: Color,
        emoteSize: CGFloat,
        maxLines: Int?,
        preferredWidth: CGFloat? = nil,
        onNonLinkTap: (() -> Void)? = nil,
        usesTextKitLayout: Bool = false,
        onContentLayoutChange: (() -> Void)? = nil
    ) {
        self.segments = segments
        self.font = font
        self.textColor = textColor
        self.emoteSize = emoteSize
        self.maxLines = maxLines
        self.preferredWidth = preferredWidth
        self.onNonLinkTap = onNonLinkTap
        self.usesTextKitLayout = usesTextKitLayout
        self.onContentLayoutChange = onContentLayoutChange

        self.textInput = DynamicAttributedTextInput(
            segments: segments.isEmpty ? [.text(" ")] : segments,
            baseFont: font,
            textColor: UIColor(textColor),
            emoteSize: emoteSize,
            maxLines: maxLines,
            typographyRole: nil
        )
    }

    init(
        input: DynamicAttributedTextInput,
        preferredWidth: CGFloat? = nil,
        onNonLinkTap: (() -> Void)? = nil,
        usesTextKitLayout: Bool = false,
        onContentLayoutChange: (() -> Void)? = nil
    ) {
        self.segments = input.segments
        self.font = input.baseFont
        self.textColor = Color(input.textColor)
        self.emoteSize = input.emoteSize
        self.maxLines = input.maxLines
        self.preferredWidth = preferredWidth
        self.onNonLinkTap = onNonLinkTap
        self.usesTextKitLayout = usesTextKitLayout
        self.onContentLayoutChange = onContentLayoutChange
        self.textInput = input
    }

    var body: some View {
        let input = resolvedTextInput

        if let plainText = input.nativePlainText, !usesTextKitLayout {
            plainTextView(input: input, plainText: plainText)
        } else {
            DynamicAttributedTextLabel(
                input: input,
                preferredWidth: preferredWidth,
                onURLTap: { url in
                    openAppURL?(url)
                },
                onNonLinkTap: onNonLinkTap,
                onContentLayoutChange: onContentLayoutChange
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func plainTextView(input: DynamicAttributedTextInput, plainText: String) -> some View {
        let text = Text(input.nativeAttributedPlainText(plainText))
            .font(input.nativeSwiftUIFont())
            .foregroundStyle(Color(input.textColor))
            .lineLimit(input.maxLines)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(width: preferredWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(plainText)

        if let onNonLinkTap {
            text
                .contentShape(Rectangle())
                .onTapGesture(perform: onNonLinkTap)
        } else {
            text
        }
    }

    private var resolvedTextInput: DynamicAttributedTextInput {
        textInput.resolvingTypography(contentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
    }
}
