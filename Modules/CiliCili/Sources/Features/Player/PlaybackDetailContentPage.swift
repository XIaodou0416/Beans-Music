import SwiftUI

enum PlaybackDetailContentMetrics {
    static let horizontalPadding: CGFloat = 12
    static let spacing: CGFloat = 10
    static let topPadding: CGFloat = 8

    static func contentWidth(for layoutWidth: CGFloat) -> CGFloat {
        max(layoutWidth - horizontalPadding * 2, 0)
    }
}

struct PlaybackDetailContentPage<Content: View>: View {
    let layoutWidth: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let spacing: CGFloat
    let background: Color
    let content: (CGFloat) -> Content

    init(
        layoutWidth: CGFloat,
        horizontalPadding: CGFloat = 0,
        topPadding: CGFloat,
        bottomPadding: CGFloat = 0,
        spacing: CGFloat,
        background: Color = Color(.systemGroupedBackground),
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.layoutWidth = layoutWidth
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.spacing = spacing
        self.background = background
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content(contentWidth)
                .padding(.horizontal, horizontalPadding)
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(width: layoutWidth, alignment: .top)
        .background(background)
    }

    private var contentWidth: CGFloat {
        max(layoutWidth - horizontalPadding * 2, 0)
    }
}
