import SwiftUI

struct BilibiliLiveList: View {
    @State private var rooms: [BilibiliLiveRoom] = []
    @State private var loading = false
    @State private var more = true
    @State private var page = 0
    @State private var error: String?
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.adaptive(minimum: 230), spacing: 12)] : [GridItem(.flexible()), GridItem(.flexible())]
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(rooms) { room in
                    Button { navigation.push(.live(room)) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Rectangle().fill(.clear).aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .overlay {
                                    GeometryReader { geo in
                                        CoverImage(url: room.cover, size: geo.size.height, aspectRatio: geo.size.width / max(geo.size.height, 1), cornerRadius: 9)
                                    }
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Text("直播 · \(room.viewers)").font(.caption2).foregroundStyle(.white)
                                        .padding(5).background(.black.opacity(0.6)).cornerRadius(5).padding(6)
                                }
                            Text(room.title).font(BeansFont.appFont(14, .medium)).foregroundStyle(Color.beansLabel).lineLimit(2)
                            Text(room.owner.name).font(.caption).foregroundStyle(Color.beansComment).lineLimit(1)
                        }
                    }.buttonStyle(.plain)
                        .onAppear { if room.id == rooms.last?.id && more && error == nil { Task { await load() } } }
                }
            }.padding(16)
            if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
            if let error { BilibiliInlineError(message: error) { Task { await load() } } }
            if !loading && error == nil && rooms.isEmpty { Text("暂无直播").foregroundStyle(.secondary) }
            Color.clear.frame(height: 150)
        }
        .task { if rooms.isEmpty { await load() } }
        .refreshable { page = 0; more = true; await load() }
    }
    private func load() async {
        guard !loading, more else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let next = page + 1
            let result = try await BilibiliAPI.shared.liveRooms(page: next)
            try Task.checkCancellation()
            var seen = Set(next == 1 ? [] : rooms.map(\.id))
            let additions = result.items.filter { seen.insert($0.id).inserted }
            rooms = next == 1 ? additions : rooms + additions
            page = next; more = result.more && !additions.isEmpty
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

struct BilibiliLivePage: View {
    let room: BilibiliLiveRoom
    @EnvironmentObject private var music: PlayerManager
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @StateObject private var video = BilibiliNativePlayer()
    @State private var pausedForChild = false
    @State private var routeDepth = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BilibiliVideoSurface(model: video, retry: play)
            Text(room.title).font(.title3.bold()).padding(.horizontal, 16)
            Button {
                pausedForChild = true
                video.pause()
                navigation.push(.up(room.owner))
            } label: {
                HStack(spacing: 12) {
                    CoverImage(url: room.owner.coverURL, size: 44, cornerRadius: 22)
                    Text(room.owner.name).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }.padding(.horizontal, 16)
            }.buttonStyle(.plain)
            Text("\(room.viewers) 人看过").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            Spacer()
        }
        .navigationTitle("直播").navigationBarTitleDisplayMode(.inline)
        .task {
            routeDepth = navigation.path.count
            play()
        }
        .onDisappear { if !pausedForChild { video.stop() } }
        .onChange(of: navigation.path.count) { count in
            if pausedForChild && count <= routeDepth {
                pausedForChild = false
                video.player?.play()
            }
        }
    }
    private func play() {
        music.pauseForBilibiliVideo()
        video.open { try await BilibiliAPI.shared.liveURLs(room.id) }
    }
}
