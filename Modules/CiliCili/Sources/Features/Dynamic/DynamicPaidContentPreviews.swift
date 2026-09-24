import SwiftUI

struct DynamicPaidContentPreview: View {
    enum Style {
        case large
        case compact
    }

    let content: DynamicPaidContent
    var style: Style = .large

    var body: some View {
        switch style {
        case .large:
            largeContent
        case .compact:
            compactContent
        }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            DynamicPaidContentCover(content: content, style: style)

            VStack(alignment: .leading, spacing: 7) {
                DynamicPaidContentTitle(content: content, style: style)
                DynamicPaidContentMetadata(content: content)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.badgeText) \(content.title)")
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            DynamicPaidContentCover(content: content, style: style)
                .frame(width: 118, height: 118 * 9 / 16)

            VStack(alignment: .leading, spacing: 7) {
                DynamicPaidContentTitle(content: content, style: style)
                DynamicPaidContentMetadata(content: content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.badgeText) \(content.title)")
    }
}
