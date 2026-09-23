import SwiftUI

extension SearchResultType {
    static var bilibiliCases: [SearchResultType] { [.all, .song, .artist, .playlist] }
    var bilibiliTitle: String {
        switch self {
        case .all: return "综合"
        case .song: return "视频"
        case .artist: return "UP主"
        case .playlist: return "合集"
        case .album: return "合集"
        }
    }
}

/// Bilibili results have their own identity and navigation. In particular an UP
/// account ID must never be synthesized from the title of a music result.
struct BilibiliSearchResults: View {
    let keyword: String
    let type: SearchResultType
    @EnvironmentObject private var player: PlayerManager
    @AppStorage(BilibiliExperience.key) private var mode = BilibiliExperience.listen.rawValue
    @State private var songs: [Song] = []
    @State private var creators: [Artist] = []
    @State private var loading = true
    @State private var error: String?
    @State private var officialPage: BilibiliOfficialPage?
    @State private var requestID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if loading && songs.isEmpty && creators.isEmpty {
                ProgressView("正在搜索").frame(maxWidth: .infinity, minHeight: 120)
            } else {
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重新搜索") { Task { await load() } }.frame(minHeight: 44)
                }
                if type == .playlist || type == .album {
                    Text("按UP主浏览合集")
                        .font(BeansFont.appFont(19, .bold)).foregroundStyle(Color.beansLabel)
                    Text("选择下方UP主，打开其官方合集列表。当前不提供独立合集搜索。")
                        .font(BeansFont.appFont(12)).foregroundStyle(Color.beansComment)
                }
                if !creators.isEmpty {
                    if type == .all {
                        Text("UP主").font(BeansFont.appFont(19, .bold)).foregroundStyle(Color.beansLabel)
                    }
                    ForEach(creators) { creator in creatorRow(creator) }
                }
                if !songs.isEmpty {
                    if type == .all {
                        Text("视频").font(BeansFont.appFont(19, .bold)).foregroundStyle(Color.beansLabel)
                    }
                    ForEach(songs, id: \.identityKey) { song in
                        Button { open(song) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CoverImage(url: song.coverURL, size: 64, aspectRatio: 16.0 / 9.0, cornerRadius: 8)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(song.name).font(BeansFont.appFont(14, .medium))
                                        .foregroundStyle(Color.beansLabel).lineLimit(2)
                                    Text(song.artists).font(BeansFont.appFont(12))
                                        .foregroundStyle(Color.beansComment).lineLimit(1)
                                    Text(song.formattedDuration).font(BeansFont.appFont(11))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button { player.playNext(song) } label: { Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            Button { officialPage = BilibiliOfficialPage.video(song) } label: { Label("视频详情与互动", systemImage: "play.rectangle") }
                        }
                    }
                }
                if songs.isEmpty && creators.isEmpty && error == nil {
                    Text("没有找到相关结果").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                }
                Button {
                    officialPage = BilibiliOfficialPage.search(keyword, up: type == .artist || type == .playlist)
                } label: {
                    Label("在官方网页继续搜索", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 180)
        .task(id: "\(type.rawValue)|\(keyword)") {
            do { try await Task.sleep(nanoseconds: 350_000_000) }
            catch { return }
            await load()
        }
        .sheet(item: $officialPage) { page in
            BilibiliOfficialBrowser(page: page).onAppear { player.pauseForBilibiliWeb() }
        }
    }

    private func creatorRow(_ creator: Artist) -> some View {
        Button {
            if type == .playlist || type == .album { officialPage = BilibiliOfficialPage.collections(creator.id) }
            else { officialPage = BilibiliOfficialPage.up(creator.id) }
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: creator.coverURL, size: 52, cornerRadius: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(creator.name).font(BeansFont.appFont(15, .medium)).foregroundStyle(Color.beansLabel)
                    Text(type == .playlist || type == .album ? "查看TA的合集" : "UP主主页")
                        .font(BeansFont.appFont(12)).foregroundStyle(Color.beansComment)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.beansComment)
            }.frame(maxWidth: .infinity, minHeight: 60).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func open(_ song: Song) {
        if mode == BilibiliExperience.video.rawValue {
            officialPage = BilibiliOfficialPage.video(song)
        } else {
            player.play(songs: songs, startAt: songs.firstIndex(where: { $0.identityKey == song.identityKey }) ?? 0)
        }
    }

    @MainActor
    private func load() async {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { loading = false; return }
        let token = UUID()
        requestID = token
        songs = []; creators = []; loading = true; error = nil
        defer { if requestID == token { loading = false } }
        do {
            switch type {
            case .song:
                let result = try await BilibiliAPI.shared.searchSongs(keyword: text, limit: 60)
                try Task.checkCancellation()
                guard requestID == token else { return }
                songs = result
            case .artist, .album, .playlist:
                let result = try await BilibiliAPI.shared.searchArtists(keyword: text, limit: 30)
                try Task.checkCancellation()
                guard requestID == token else { return }
                creators = result
            case .all:
                async let videoResult = BilibiliAPI.shared.searchSongs(keyword: text, limit: 20)
                async let upResult = BilibiliAPI.shared.searchArtists(keyword: text, limit: 6)
                let tracks = try? await videoResult
                let accounts = try? await upResult
                try Task.checkCancellation()
                guard requestID == token else { return }
                songs = tracks ?? []
                creators = accounts ?? []
                if tracks == nil && accounts == nil { error = "B站搜索暂不可用，请稍后重试或打开官方网页" }
            }
        } catch is CancellationError { }
        catch { if requestID == token { self.error = error.localizedDescription } }
    }
}
