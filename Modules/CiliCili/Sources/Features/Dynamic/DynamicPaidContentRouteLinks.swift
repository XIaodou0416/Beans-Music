import SwiftUI

struct DynamicPaidContentRouteLink<Label: View>: View {
    let content: DynamicPaidContent
    let video: VideoItem?
    @ViewBuilder let label: () -> Label
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let video {
            VideoRouteLink(video) {
                label()
            }
        } else if let url = content.normalizedJumpURL {
            Button {
                openURL(url)
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            label()
                .opacity(0.78)
        }
    }
}

struct DynamicPaidArticleTextRouteLink<Label: View>: View {
    let content: DynamicPaidContent
    let chargeURL: URL?
    @ViewBuilder let label: () -> Label
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let chargeURL {
            Button {
                openURL(chargeURL)
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            label()
        }
    }
}
