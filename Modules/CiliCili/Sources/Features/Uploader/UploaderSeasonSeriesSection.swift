import SwiftUI

struct UploaderSeasonSeriesSection: View {
    @ObservedObject var viewModel: UploaderViewModel

    private var lastItemID: String? {
        viewModel.seasonSeriesItems.last?.id
    }

    var body: some View {
        LazyVStack(spacing: 10) {
            if viewModel.seasonSeriesItems.isEmpty && viewModel.seasonSeriesState.isLoading {
                UploaderSeasonSeriesLoadingState()
            } else if viewModel.seasonSeriesItems.isEmpty {
                emptyOrErrorState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                ForEach(viewModel.seasonSeriesItems) { item in
                    UploaderSeasonSeriesRouteCard(owner: viewModel.seedOwner, item: item)
                        .task {
                            await viewModel.loadMoreSeasonSeriesIfNeeded(current: item.id == lastItemID ? item : nil)
                        }
                }

                footer
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var emptyOrErrorState: some View {
        if case .failed(let message) = viewModel.seasonSeriesState {
            ErrorStateView(title: "合集加载失败", message: message) {
                Task { await viewModel.refreshSeasonSeries() }
            }
        } else {
            EmptyStateView(title: "暂无合集", systemImage: "rectangle.stack", message: "这个 UP 主还没有可展示的合集或列表。")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.seasonSeriesState.isLoading {
            InlineLoadingStateView(title: "正在加载合集")
                .padding(.vertical, 6)
        } else if viewModel.hasMoreSeasonSeriesItems {
            Button {
                Task { await viewModel.loadMoreSeasonSeries() }
            } label: {
                Label("加载更多", systemImage: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .padding(.top, 6)
        } else {
            Text("没有更多合集了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }
}

private struct UploaderSeasonSeriesRouteCard: View {
    let owner: VideoOwner
    let item: UploaderSeasonSeriesItem

    var body: some View {
        if item.detailKind != nil {
            NavigationLink {
                UploaderSeasonSeriesDetailView(owner: owner, item: item)
            } label: {
                UploaderSeasonSeriesCard(item: item)
            }
            .buttonStyle(.plain)
        } else {
            UploaderSeasonSeriesCard(item: item)
        }
    }
}

private struct UploaderSeasonSeriesLoadingState: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                UploaderSeasonSeriesSkeletonCard()
            }
        }
        .accessibilityLabel("正在加载合集")
    }
}

private struct UploaderSeasonSeriesSkeletonCard: View {
    private let coverSize = CGSize(width: 132, height: 74)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SkeletonBlock(width: coverSize.width, height: coverSize.height, shape: .rounded(8))

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(height: 15, shape: .rounded(5))
                SkeletonBlock(width: 132, height: 15, shape: .rounded(5))
                SkeletonBlock(width: 108, height: 11, shape: .capsule)
                SkeletonBlock(width: 180, height: 12, shape: .rounded(5))
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct UploaderSeasonSeriesCard: View {
    let item: UploaderSeasonSeriesItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            UploaderSeasonSeriesCover(item: item)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                metadata

                if let archive = item.previewArchive {
                    UploaderSeasonSeriesPreview(archive: archive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            Label("\(item.total ?? 0) 个视频", systemImage: "play.rectangle.stack")

            if !BiliFormatters.publishDate(item.updateTime).isEmpty,
               BiliFormatters.publishDate(item.updateTime) != "-" {
                Label(BiliFormatters.publishDate(item.updateTime), systemImage: "calendar")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct UploaderSeasonSeriesCover: View {
    private let size = CGSize(width: 132, height: 74)

    let item: UploaderSeasonSeriesItem

    var body: some View {
        let cover = item.cover
        ZStack(alignment: .bottomTrailing) {
            CachedRemoteImage(
                url: cover.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 320, height: 180)) },
                fallbackURL: cover.flatMap(URL.init(string:)),
                targetPixelSize: 360,
                animatesAppearance: false
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        Image(systemName: "rectangle.stack")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            Text("\(item.kindTitle): \(item.total ?? 0)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.62), in: Capsule())
                .padding(6)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .mediaShadow(.subtle)
    }
}

private struct UploaderSeasonSeriesPreview: View {
    let archive: UploaderSeasonSeriesArchive

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("最新：\(archive.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                Label(BiliFormatters.compactCount(archive.stat?.view), systemImage: "play.fill")

                if archive.duration != nil {
                    Label(BiliFormatters.duration(archive.duration), systemImage: "clock")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
    }
}
