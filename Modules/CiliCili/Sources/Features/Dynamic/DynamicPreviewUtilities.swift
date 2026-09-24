import SwiftUI

struct FixedAspectPreview<Content: View>: View {
    let aspectRatio: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipped()
    }
}

struct DynamicVideoPlayBadge: View {
    var size: CGFloat = 48
    var iconSize: CGFloat = 18

    var body: some View {
        VideoCoverPlayBadge(size: size, iconSize: iconSize)
    }
}
