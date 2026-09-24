import SwiftUI

extension SearchResultType {
    static var bilibiliCases: [SearchResultType] { [.all, .song, .artist, .playlist] }
    var bilibiliTitle: String {
        switch self {
        case .all: return "综合"
        case .song: return "视频"
        case .artist: return "UP主"
        case .album, .playlist: return "合集"
        }
    }
}

struct BilibiliSearchResults: View {
    let keyword: String
    let type: SearchResultType
    var onVideo: ((Song) -> Void)? = nil
    @State private var videos: [BilibiliFeedVideo] = []
    @State private var creators: [Artist] = []
    @State private var collections: [BilibiliSeries] = []
    @State private var page = 0
    @State private var more = true
    @State private var loading = true
    @State private var error: String?
    @State private var token = UUID()
    @EnvironmentObject private var navigation: BilibiliNavigationState

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if type == .playlist || type == .album {
                Text("相关视频所属的合集").font(.headline)
                Text("根据当前搜索结果中的视频查找真实合集；也可进入UP主页浏览全部合集。")
                    .font(.caption).foregroundStyle(Color.beansComment)
            }
            if !creators.isEmpty {
                if type == .all { Text("UP主").font(.headline) }
                ForEach(creators) { creator in
                    Button { navigation.push(.up(creator)) } label: {
                        HStack(spacing: 12) {
                            CoverImage(url: creator.coverURL, size: 50, cornerRadius: 25)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(creator.name).font(BeansFont.appFont(15, .semibold)).foregroundStyle(Color.beansLabel)
                                Text("UP主主页 · 投稿与合集").font(.caption).foregroundStyle(Color.beansComment)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.beansComment)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .onAppear { if type == .artist && creator.id == creators.last?.id { nextIfNeeded() } }
                }
            }
            if !collections.isEmpty {
                ForEach(collections) { collection in
                    Button { navigation.push(.collection(collection)) } label: { BilibiliCollectionRow(collection: collection) }.buttonStyle(.plain)
                }
            }
            if !videos.isEmpty {
                if type == .all { Text("视频").font(.headline) }
                BilibiliVideoRows(items: videos, onAppearItem: { id in
                    if id == videos.last?.id { nextIfNeeded() }
                }, onVideo: onVideo)
            }
            if loading { ProgressView("正在搜索").frame(maxWidth: .infinity, minHeight: 90) }
            if let error { BilibiliInlineError(message: error) { Task { await load(reset: page == 0) } } }
            if !loading && error == nil && videos.isEmpty && creators.isEmpty && collections.isEmpty {
                Text("当前页未找到相关\(type.bilibiliTitle)").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
            if !loading && error == nil && more && (type == .playlist || type == .album) {
                Button("继续查找下一页合集") { Task { await load(reset: false) } }.frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 100)
        .task(id: "\(type.rawValue)|\(keyword)") {
            token = UUID()
            videos = []; creators = []; collections = []; page = 0; more = true; error = nil; loading = true
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            await load(reset: true)
        }
    }
    private func nextIfNeeded() {
        guard more, !loading, error == nil else { return }
        Task { await load(reset: false) }
    }
    @MainActor private func load(reset: Bool) async {
        if !reset && (loading || !more) { return }
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { loading = false; return }
        let request = token
        loading = true; error = nil
        let next = reset ? 1 : page + 1
        defer { if token == request { loading = false } }
        do {
            switch type {
            case .all, .song:
                let result = try await BilibiliAPI.shared.videoSearch(text, page: next)
                try Task.checkCancellation()
                guard token == request else { return }
                var seen = Set(reset ? [] : videos.map(\.id))
                let additions = result.items.filter { seen.insert($0.id).inserted }
                videos = reset ? additions : videos + additions
                more = result.more
                if type == .all && reset {
                    if let users = try? await BilibiliAPI.shared.upSearch(text, page: 1) {
                        try Task.checkCancellation()
                        guard token == request else { return }
                        creators = Array(users.items.prefix(4))
                    }
                }
            case .artist:
                let result = try await BilibiliAPI.shared.upSearch(text, page: next)
                try Task.checkCancellation()
                guard token == request else { return }
                var seen = Set(reset ? [] : creators.map(\.id))
                let additions = result.items.filter { seen.insert($0.id).inserted }
                creators = reset ? additions : creators + additions
                more = result.more
            case .album, .playlist:
                let result = try await BilibiliAPI.shared.videoSearch(text, page: next)
                try Task.checkCancellation()
                // Bounded to the visible search page. Each result must resolve
                // to an actual season, never a video renamed as an album.
                var found: [BilibiliSeries] = []
                var resolved = 0
                for item in result.items.prefix(6) {
                    if let info = try? await BilibiliAPI.shared.nativeVideo(item.song) {
                        resolved += 1
                        if let collection = info.collection { found.append(collection) }
                    }
                    try Task.checkCancellation()
                    guard token == request else { return }
                }
                if !result.items.isEmpty && resolved == 0 { throw BilibiliError(message: "合集信息加载失败，请重试") }
                var seen = Set(reset ? [] : collections.map(\.id))
                let additions = found.filter { seen.insert($0.id).inserted }
                collections = reset ? additions : collections + additions
                more = result.more
            }
            guard token == request else { return }
            page = next
        } catch is CancellationError { }
        catch { if token == request { self.error = error.localizedDescription } }
    }
}
