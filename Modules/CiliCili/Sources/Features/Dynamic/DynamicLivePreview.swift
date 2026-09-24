import SwiftUI

struct DynamicLivePreview: View {
    enum Style {
        case large
        case compact
    }

    let live: DynamicLive
    var style: Style = .large

    var body: some View {
        switch style {
        case .large:
            largeContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("鐩存挱 \(live.displayTitle)")
        case .compact:
            compactContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("鐩存挱 \(live.displayTitle)")
        }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            DynamicLiveCover(live: live, showsCenterBadge: false)

            DynamicLiveTitle(live: live, style: style)
                .padding(.horizontal, 10)

            DynamicLiveMetadata(live: live)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            DynamicLiveCover(live: live, showsCenterBadge: false)
                .frame(width: 118, height: 118 * 9 / 16)

            VStack(alignment: .leading, spacing: 7) {
                DynamicLiveTitle(live: live, style: style)

                DynamicLiveMetadata(live: live)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
