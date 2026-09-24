import SwiftUI

enum PlaybackDetailPlayerMetrics {
    static func standardHeight(for width: CGFloat) -> CGFloat {
        width * 9 / 16
    }
}

struct PlaybackDetailPlayerSurface<Content: View>: View {
    let width: CGFloat?
    let height: CGFloat
    let background: Color
    let content: () -> Content

    init(
        width: CGFloat? = nil,
        height: CGFloat,
        background: Color = .black,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.height = height
        self.background = background
        self.content = content
    }

    var body: some View {
        content()
            .frame(width: width)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background)
            .clipped()
    }
}
