import SwiftUI

struct SearchVideoResultRow: View, Equatable {
    private let display: VideoCardDisplayModel
    private let coverSize = CGSize(width: 140, height: 88)

    init(video: VideoItem) {
        self.display = VideoCardDisplayModel(video: video)
    }

    var body: some View {
        VideoCardBorderedCompactBody(
            display: display,
            coverSize: coverSize,
            leadingMetadata: .duration,
            showsRecommendReason: false,
            showsCoverDurationBadge: false
        )
        .equatable()
    }
}

struct SearchVideoResultSkeletonRow: View {
    private let coverSize = CGSize(width: 140, height: 88)
    private let cornerRadius: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SkeletonBlock(width: coverSize.width, height: coverSize.height, shape: .rounded(12))

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    SkeletonBlock(height: 15, shape: .rounded(5))
                    SkeletonBlock(width: 132, height: 15, shape: .rounded(5))
                }
                .frame(minHeight: 36, alignment: .topLeading)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 5) {
                    SkeletonBlock(width: 86, height: 12, shape: .capsule)

                    HStack(spacing: 8) {
                        SkeletonBlock(width: 58, height: 11, shape: .capsule)
                        Spacer(minLength: 6)
                        SkeletonBlock(width: 46, height: 11, shape: .capsule)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: coverSize.height, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 108, alignment: .topLeading)
        .compactVideoResultSurface(cornerRadius: cornerRadius)
        .allowsHitTesting(false)
        .accessibilityLabel("正在加载搜索结果")
    }
}
