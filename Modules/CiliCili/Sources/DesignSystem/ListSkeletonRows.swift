import SwiftUI

struct CommentLoadingSkeletonList: View {
    var count: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                CommentLoadingSkeletonRow()
                    .padding(.vertical, 12)

                if index != count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .accessibilityLabel("正在加载评论")
    }
}

struct CommentLoadingSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SkeletonBlock(width: 40, height: 40, shape: .circle)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(width: 104, height: 13, shape: .capsule)
                SkeletonBlock(height: 14, shape: .rounded(5))
                SkeletonBlock(width: 230, height: 14, shape: .rounded(5))

                HStack(spacing: 12) {
                    SkeletonBlock(width: 52, height: 10, shape: .capsule)
                    SkeletonBlock(width: 38, height: 10, shape: .capsule)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SearchResultSkeletonRow: View {
    private let coverSize = CGSize(width: 168, height: 105)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            placeholderBlock(cornerRadius: 18)
                .frame(width: coverSize.width, height: coverSize.height)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    placeholderBlock(height: 15)
                    placeholderBlock(width: 128, height: 15)
                }
                .frame(minHeight: 38, alignment: .topLeading)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    placeholderBlock(width: 96, height: 11)

                    HStack {
                        placeholderBlock(width: 62, height: 10)
                        Spacer(minLength: 6)
                        placeholderBlock(width: 48, height: 10)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: max(coverSize.height - 20, 1), alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: coverSize.height, alignment: .topLeading)
        .videoCardBorderedSurface(cornerRadius: 18, showsShadow: false)
        .accessibilityLabel("正在加载搜索结果")
    }

    private func placeholderBlock(width: CGFloat? = nil, height: CGFloat? = nil, cornerRadius: CGFloat = 5) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: width, height: height)
    }
}
