import SwiftUI

struct BilibiliFeedVideo: Identifiable, Codable {
    let song: Song
    let ownerAvatarURL: URL?
    let playCount: Int
    let danmakuCount: Int
    var id: String { song.identityKey }

    static func countLabel(_ count: Int) -> String {
        if count >= 100_000_000 { return String(format: "%.1f亿", Double(count) / 100_000_000) }
        if count >= 10_000 { return String(format: "%.1f万", Double(count) / 10_000) }
        return String(max(0, count))
    }
}

@MainActor
final class BilibiliHomeFeedStore: ObservableObject {
    static let shared = BilibiliHomeFeedStore()
    @Published private(set) var videos: [BilibiliFeedVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    @Published private(set) var query = ""
    @Published private(set) var channel = BilibiliChannel.recommended
    private var page = 0
    private var failedPage = 1
    private var generation = UUID()
    private var loadedAt = Date.distantPast
    private let cacheKey = "beans.bilibili.home.videos.v1"
    private struct Snapshot: Codable {
        let videos: [BilibiliFeedVideo]
        let page: Int
        let hasMore: Bool
        let savedAt: Date
    }
    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(Snapshot.self, from: data) {
            videos = cached.videos; page = cached.page; hasMore = cached.hasMore; loadedAt = cached.savedAt
        }
    }
    func select(channel nextChannel: BilibiliChannel, query text: String = "", force: Bool = false) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = nextChannel != channel || text != query
        if changed {
            generation = UUID(); channel = nextChannel; query = text
            isLoading = false; isLoadingMore = false
            videos = []; page = 0; hasMore = true; error = nil; loadedAt = .distantPast
        }
        if force || changed || videos.isEmpty || Date().timeIntervalSince(loadedAt) > 900 {
            await loadFirst(force: force || changed)
        }
    }
    func search(_ query: String) async { await select(channel: channel, query: query, force: true) }
    func loadFirst(force: Bool = false) async {
        guard !isLoading || force else { return }
        if !force, !videos.isEmpty, Date().timeIntervalSince(loadedAt) < 900 { return }
        await load(page: 1, reset: true, force: force)
    }
    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore, page > 0 else { return }
        await load(page: page + 1, reset: false, force: false)
    }
    private func load(page next: Int, reset: Bool, force: Bool) async {
        if reset { generation = UUID(); isLoading = true; isLoadingMore = false }
        else { isLoadingMore = true }
        let token = generation, requestedQuery = query, requestedChannel = channel
        error = nil
        defer {
            if token == generation {
                if reset { isLoading = false } else { isLoadingMore = false }
            }
        }
        do {
            let result: (items: [BilibiliFeedVideo], more: Bool)
            if requestedQuery.isEmpty {
                result = try await BilibiliAPI.shared.channelVideos(requestedChannel, page: next, force: force)
            } else {
                result = try await BilibiliAPI.shared.videoSearch(requestedQuery, page: next)
            }
            try Task.checkCancellation()
            guard token == generation else { return }
            var seen = Set(reset ? [] : videos.map(\.id))
            let additions = result.items.filter { seen.insert($0.id).inserted }
            videos = reset ? additions : videos + additions
            page = next; hasMore = result.more; loadedAt = Date()
            if reset && query.isEmpty && channel == .recommended {
                let snapshot = Snapshot(videos: videos, page: 1, hasMore: hasMore, savedAt: loadedAt)
                if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: cacheKey) }
            }
        } catch is CancellationError { }
        catch { if token == generation { failedPage = next; self.error = error.localizedDescription } }
    }
    func loadMoreIfNeeded(id: String) async {
        guard error == nil, videos.suffix(6).contains(where: { $0.id == id }) else { return }
        await loadMore()
    }
    func retry() async {
        if failedPage == 1 { await loadFirst(force: true) } else { await loadMore() }
    }
}

struct BilibiliHomeFeed: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @ObservedObject private var store = BilibiliHomeFeedStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.sizeCategory) private var sizeCategory
    @AppStorage(BilibiliExperience.key) private var mode = BilibiliExperience.listen.rawValue

    private var columns: [GridItem] {
        if sizeCategory.isAccessibilityCategory { return [GridItem(.flexible())] }
        if horizontalSizeClass == .regular { return [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 12, alignment: .top)] }
        return [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Text(store.query.isEmpty ? (store.channel == .recommended ? "热门推荐" : store.channel.title) : "搜索结果")
                .font(BeansFont.appFont(20, .bold)).foregroundStyle(Color.beansLabel)
            if store.videos.isEmpty {
                if let error = store.error {
                    ErrorStateView(message: error) { Task { await store.loadFirst(force: true) } }
                } else if !store.isLoading && !store.query.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", text: "没有找到相关视频")
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 9) {
                                RoundedRectangle(cornerRadius: 10).fill(Color.beansGlassFill)
                                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                RoundedRectangle(cornerRadius: 3).fill(Color.beansGlassFill).frame(height: 14)
                                RoundedRectangle(cornerRadius: 3).fill(Color.beansGlassFill).frame(width: 80, height: 10)
                            }
                        }
                    }
                    .accessibilityLabel("正在加载推荐视频")
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(store.videos) { video in
                        BilibiliFeedCard(video: video) {
                            BeansHaptics.tap()
                            let tracks = store.videos.map(\.song)
                            if mode == BilibiliExperience.video.rawValue { navigation.push(.video(video.song)) }
                            else { player.play(songs: tracks, startAt: tracks.firstIndex(where: { $0.identityKey == video.id }) ?? 0) }
                        }
                        .onAppear { Task { await store.loadMoreIfNeeded(id: video.id) } }
                        .contextMenu {
                            Button { player.playNext(video.song) } label: { Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            Button { navigation.push(.video(video.song)) } label: { Label("视频详情与评论", systemImage: "play.rectangle") }
                        }
                    }
                }
                if let error = store.error {
                    VStack(spacing: 8) {
                        Text(error).font(BeansFont.appFont(12)).foregroundStyle(Color.beansComment)
                        Button("重试") {
                            Task { await store.retry() }
                        }.frame(minHeight: 44)
                    }.frame(maxWidth: .infinity)
                } else if store.hasMore {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                        .id(store.videos.last?.id)
                        .onAppear { Task { await store.loadMore() } }
                } else {
                    Text("暂时没有更多视频").font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }
}

private struct BilibiliFeedCard: View {
    let video: BilibiliFeedVideo
    let play: () -> Void
    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 9) {
                Rectangle().fill(Color.clear)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        GeometryReader { geometry in
                            CoverImage(url: video.song.coverURL, size: geometry.size.height,
                                       aspectRatio: geometry.size.width / max(geometry.size.height, 1), cornerRadius: 10)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 42)
                            .overlay(alignment: .bottom) {
                                HStack(spacing: 4) {
                                    if video.playCount > 0 {
                                        Image(systemName: "play.rectangle").font(.system(size: 10))
                                        Text(BilibiliFeedVideo.countLabel(video.playCount))
                                    }
                                    Spacer(minLength: 2)
                                    Text(video.song.formattedDuration).monospacedDigit()
                                }
                                .font(BeansFont.appFont(10, .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.bottom, 6)
                            }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(video.song.name)
                    .font(BeansFont.appFont(14, .medium))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    if let avatar = video.ownerAvatarURL {
                        CoverImage(url: avatar, size: 18, cornerRadius: 9)
                    } else {
                        Text("UP").font(BeansFont.appFont(8, .semibold))
                            .padding(.horizontal, 2).overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.beansComment, lineWidth: 0.7))
                    }
                    Text(video.song.artists).font(BeansFont.appFont(11)).lineLimit(1)
                    Spacer(minLength: 0)
                }.foregroundStyle(Color.beansComment)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(video.song.name)，UP主 \(video.song.artists)，\(video.song.formattedDuration)")
        .accessibilityHint("播放视频音频")
    }
}
