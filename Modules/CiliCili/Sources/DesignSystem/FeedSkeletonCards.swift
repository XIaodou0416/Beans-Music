import SwiftUI

struct VideoFeedSkeletonCard: View {
    enum Style {
        case singleColumn
        case borderedSingleColumn(coverSize: CGSize)
        case grid
    }

    let style: Style

    var body: some View {
        switch style {
        case .singleColumn:
            singleColumnBody
        case .borderedSingleColumn(let coverSize):
            borderedSingleColumnBody(coverSize: coverSize)
        case .grid:
            gridBody
        }
    }

    private var singleColumnBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonAspectBlock(cornerRadius: 18)

            HStack(alignment: .center, spacing: 9) {
                SkeletonBlock(width: 34, height: 34, shape: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    SkeletonBlock(height: 18, shape: .rounded(5))
                    SkeletonBlock(width: 206, height: 13, shape: .capsule)
                }
                .frame(height: 34, alignment: .center)
            }
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 9)
        .padding(.bottom, 14)
        .accessibilityLabel("正在加载视频")
    }

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonAspectBlock(cornerRadius: 15)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonBlock(height: 15, shape: .rounded(5))
                    SkeletonBlock(width: 104, height: 15, shape: .rounded(5))
                }
                .frame(minHeight: 36, alignment: .topLeading)

                HStack(spacing: 4) {
                    SkeletonBlock(width: 14, height: 14, shape: .circle)
                    SkeletonBlock(width: 92, height: 11, shape: .capsule)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityLabel("正在加载视频")
    }

    private func borderedSingleColumnBody(coverSize: CGSize) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: coverSize.width, height: coverSize.height)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonBlock(height: 15, shape: .rounded(5))
                    SkeletonBlock(width: 136, height: 15, shape: .rounded(5))
                }
                .frame(minHeight: 38, alignment: .topLeading)

                Spacer(minLength: 0)

                SkeletonBlock(width: 118, height: 11, shape: .capsule)

                HStack {
                    SkeletonBlock(width: 62, height: 11, shape: .capsule)
                    Spacer(minLength: 6)
                    SkeletonBlock(width: 54, height: 11, shape: .capsule)
                }
            }
            .frame(maxWidth: .infinity, minHeight: coverSize.height, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(coverSize.height + 20, 108), alignment: .topLeading)
        .compactVideoResultSurface(cornerRadius: 18)
        .padding(.vertical, 6)
        .accessibilityLabel("正在加载视频")
    }
}

struct DynamicFeedSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SkeletonBlock(width: 36, height: 36, shape: .circle)

                SkeletonBlock(width: 132, height: 14, shape: .capsule)

                Spacer(minLength: 10)

                SkeletonBlock(width: 52, height: 11, shape: .capsule)
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(height: 17, shape: .rounded(5))
                SkeletonBlock(width: 260, height: 17, shape: .rounded(5))
            }
            .padding(.horizontal, 12)

            SkeletonAspectBlock(cornerRadius: 20)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                SkeletonBlock(width: 74, height: 28, shape: .capsule)
                SkeletonBlock(width: 74, height: 28, shape: .capsule)
                SkeletonBlock(width: 74, height: 28, shape: .capsule)
            }
            .padding(.horizontal, 12)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 21)
        .padding(.bottom, 23)
        .accessibilityLabel("正在加载动态")
    }
}

struct LiveRoomSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonAspectBlock(aspectRatio: 16 / 10, cornerRadius: 14)
                .videoCardBorderedCover()

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonBlock(height: 15, shape: .rounded(5))
                    SkeletonBlock(width: 104, height: 15, shape: .rounded(5))
                }
                .frame(minHeight: 36, alignment: .topLeading)

                HStack(spacing: 6) {
                    SkeletonBlock(width: 14, height: 14, shape: .circle)
                    SkeletonBlock(width: 72, height: 11, shape: .capsule)
                    Spacer(minLength: 6)
                    SkeletonBlock(width: 46, height: 11, shape: .capsule)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .videoCardBorderedSurface(cornerRadius: 18)
        .accessibilityLabel("正在加载直播间")
    }
}
