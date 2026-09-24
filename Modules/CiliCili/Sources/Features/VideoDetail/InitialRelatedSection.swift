import SwiftUI

struct InitialRelatedSection: View {
    let layoutWidth: CGFloat

    var body: some View {
        let layout = VideoDetailRelatedListLayout(layoutWidth: layoutWidth)

        VStack(alignment: .leading, spacing: VideoDetailRelatedStyle.sectionSpacing) {
            VideoDetailRelatedHeader(isLoading: true)
                .padding(.horizontal, layout.horizontalPadding)

            VideoDetailRelatedPlaceholderList(layout: layout)
                .padding(.horizontal, layout.horizontalPadding)
        }
        .frame(width: layoutWidth, alignment: .leading)
        .padding(.top, VideoDetailRelatedStyle.sectionTopPadding)
        .padding(.bottom, VideoDetailRelatedStyle.sectionBottomPadding)
        .allowsHitTesting(false)
    }
}
