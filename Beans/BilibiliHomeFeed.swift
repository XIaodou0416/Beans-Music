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
            videos = cached.videos
            page = cached.page
            hasMore = cached.hasMore
            loadedAt = cached.savedAt
        }
    }

    func loadFirst(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, !videos.isEmpty, Date().timeIntervalSince(loadedAt) < 900 { return }
        let token = UUID()
        generation = token
        isLoading = true
        isLoadingMore = false
        error = nil
        defer { if generation == token { isLoading = false } }
        do {
            let result = try await BilibiliAPI.shared.popularVideos(page: 1, force: force)
            try Task.checkCancellation()
            guard generation == token else { return }
            guard !result.videos.isEmpty else { throw BilibiliError(message: "暂时没有推荐视频，请稍后刷新") }
            var seen = Set<String>()
            videos = result.videos.filter { seen.insert($0.id).inserted }
            page = 1
            hasMore = result.hasMore
            loadedAt = Date()
            persist()
        } catch is CancellationError { }
        catch { if generation == token { failedPage = 1; self.error = error.localizedDescription } }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore, page > 0 else { return }
        let token = generation
        isLoadingMore = true
        error = nil
        defer { if generation == token { isLoadingMore = false } }
        do {
            let result = try await BilibiliAPI.shared.popularVideos(page: page + 1)
            try Task.checkCancellation()
            guard generation == token else { return }
            var seen = Set(videos.map(\.id))
            let additions = result.videos.filter { seen.insert($0.id).inserted }
            videos += additions
            page += 1
            hasMore = result.hasMore && !additions.isEmpty
            persist()
        } catch is CancellationError { }
        catch { if generation == token { failedPage = page + 1; self.error = error.localizedDescription } }
    }

    func retry() async {
        if failedPage == 1 { await loadFirst(force: true) }
        else { await loadMore() }
    }

    private func persist() {
        // Keep a small first-page snapshot; pagination always resumes from page 2
        // after restarting, without skipping pages removed by the cache cap.
        let snapshot = Snapshot(videos: Array(videos.prefix(20)), page: 1,
                                hasMore: videos.count > 20 || hasMore, savedAt: loadedAt)
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: cacheKey) }
    }
}

struct BilibiliHomeFeed: View {
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var store = BilibiliHomeFeedStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.sizeCategory) private var sizeCategory

    private var columns: [GridItem] {
        if sizeCategory.isAccessibilityCategory { return [GridItem(.flexible())] }
        if horizontalSizeClass == .regular { return [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 12, alignment: .top)] }
        return [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("热门推荐")
                    .font(BeansFont.appFont(20, .bold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Button {
                    Task { await store.loadFirst(force: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(BeansFont.appFont(13, .medium))
                        .frame(minHeight: 44)
                }
                .disabled(store.isLoading)
            }
            if store.videos.isEmpty {
                if let error = store.error {
                    ErrorStateView(message: error) { Task { await store.loadFirst(force: true) } }
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
                            player.play(songs: tracks, startAt: tracks.firstIndex(where: { $0.identityKey == video.id }) ?? 0)
                        }
                        .contextMenu {
                            Button { player.playNext(video.song) } label: { Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            if let url = video.song.officialURL { Link(destination: url) { Label("在哔哩哔哩打开", systemImage: "arrow.up.right.square") } }
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
                    Button { Task { await store.loadMore() } } label: {
                        Group {
                            if store.isLoadingMore { ProgressView() }
                            else { Text("加载更多").font(BeansFont.appFont(13)) }
                        }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(store.isLoadingMore)
                    .id(store.videos.last?.id)
                    .onAppear { Task { await store.loadMore() } }
                } else {
                    Text("暂时没有更多视频").font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .task { await store.loadFirst() }
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
                                    Image(systemName: "play.rectangle").font(.system(size: 10))
                                    Text(BilibiliFeedVideo.countLabel(video.playCount))
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
