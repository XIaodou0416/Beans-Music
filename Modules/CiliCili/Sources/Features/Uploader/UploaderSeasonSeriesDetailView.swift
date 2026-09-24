import Combine
import SwiftUI

struct UploaderSeasonSeriesDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var viewModel: UploaderSeasonSeriesDetailViewModel

    init(owner: VideoOwner, item: UploaderSeasonSeriesItem) {
        _viewModel = StateObject(wrappedValue: UploaderSeasonSeriesDetailViewModel(owner: owner, item: item))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                controls
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                content
            }
        }
        .navigationTitle(viewModel.item.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh(api: dependencies.api)
        }
        .task {
            await viewModel.loadIfNeeded(api: dependencies.api)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(UploaderSeasonSeriesArchiveSort.allCases) { sort in
                    Button {
                        Task { await viewModel.changeSort(sort, api: dependencies.api) }
                    } label: {
                        Label(sort.title, systemImage: sort == viewModel.sort ? "checkmark" : "circle")
                    }
                }
            } label: {
                Label(viewModel.sort.title, systemImage: "arrow.up.arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            Spacer(minLength: 0)

            if let totalCount = viewModel.totalCount ?? viewModel.item.total {
                Text("\(totalCount) 个视频")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.videos.isEmpty && viewModel.state.isLoading {
            UploaderSeasonSeriesDetailLoadingRows()
                .padding(.horizontal, 16)
                .padding(.top, 4)
        } else if viewModel.videos.isEmpty {
            emptyOrErrorState
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
                .padding(.horizontal, 16)
        } else {
            videoRows
        }
    }

    private var videoRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.videos) { video in
                VideoRouteLink(video) {
                    VideoCompactListRow(
                        display: VideoCardDisplayModel(video: video),
                        coverSize: CGSize(width: 132, height: 74),
                        coverCornerRadius: 8,
                        showsCoverBorder: true,
                        authorStyle: .plain,
                        metadataStyle: .search
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .task {
                    await viewModel.loadMoreIfNeeded(api: dependencies.api, current: video)
                }

                if video.id != viewModel.videos.last?.id {
                    Divider()
                        .padding(.leading, 160)
                }
            }

            footer
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var emptyOrErrorState: some View {
        if case .failed(let message) = viewModel.state {
            ErrorStateView(title: "视频加载失败", message: message) {
                Task { await viewModel.refresh(api: dependencies.api) }
            }
        } else {
            EmptyStateView(title: "暂无视频", systemImage: "play.rectangle", message: "这个合集里暂时没有可展示的视频。")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.state.isLoading {
            InlineLoadingStateView(title: "正在加载视频")
                .padding(.vertical, 8)
        } else if viewModel.hasMore {
            Button {
                Task { await viewModel.loadMore(api: dependencies.api) }
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
            .padding(.vertical, 10)
        } else {
            Text("没有更多视频了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

@MainActor
private final class UploaderSeasonSeriesDetailViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var state: LoadingState = .idle
    @Published var sort: UploaderSeasonSeriesArchiveSort = .desc
    @Published private(set) var totalCount: Int?
    @Published private(set) var hasMore = true

    let owner: VideoOwner
    let item: UploaderSeasonSeriesItem

    private var page = 1

    init(owner: VideoOwner, item: UploaderSeasonSeriesItem) {
        self.owner = owner
        self.item = item
        totalCount = item.total
    }

    func loadIfNeeded(api: BiliAPIClient) async {
        guard videos.isEmpty, !state.isLoading else { return }
        await refresh(api: api)
    }

    func refresh(api: BiliAPIClient) async {
        guard let kind = item.detailKind else {
            state = .failed("缺少合集 ID")
            return
        }
        state = .loading
        page = 1
        hasMore = true
        do {
            apply(try await api.fetchUploaderSeasonSeriesArchivePage(
                mid: owner.mid,
                owner: owner,
                kind: kind,
                page: page,
                sort: sort
            ), appending: false)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func changeSort(_ sort: UploaderSeasonSeriesArchiveSort, api: BiliAPIClient) async {
        guard sort != self.sort, !state.isLoading else { return }
        self.sort = sort
        videos = []
        await refresh(api: api)
    }

    func loadMoreIfNeeded(api: BiliAPIClient, current video: VideoItem?) async {
        guard let video, videos.last?.id == video.id else { return }
        await loadMore(api: api)
    }

    func loadMore(api: BiliAPIClient) async {
        guard let kind = item.detailKind, hasMore, !state.isLoading else { return }
        state = .loading
        page += 1
        do {
            apply(try await api.fetchUploaderSeasonSeriesArchivePage(
                mid: owner.mid,
                owner: owner,
                kind: kind,
                page: page,
                sort: sort
            ), appending: true)
            state = .loaded
        } catch {
            page = max(1, page - 1)
            state = .failed(error.localizedDescription)
        }
    }

    private func apply(_ result: UploaderSeasonSeriesArchivePageResult, appending: Bool) {
        totalCount = result.totalCount ?? totalCount
        if appending {
            let existing = Set(videos.map(\.id))
            let unique = result.videos.filter { !existing.contains($0.id) }
            videos.append(contentsOf: unique)
            hasMore = result.hasMore && !unique.isEmpty
        } else {
            videos = result.videos
            hasMore = result.hasMore && !result.videos.isEmpty
        }
    }
}

private struct UploaderSeasonSeriesDetailLoadingRows: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<8, id: \.self) { _ in
                VideoCompactListPlaceholderRow(
                    coverSize: CGSize(width: 132, height: 74),
                    cornerRadius: 8,
                    metadataStyle: .search
                )
            }
        }
    }
}
