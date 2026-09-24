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
    @State private var tab = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    BilibiliVideoSurface(model: video, retry: play)
                    LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                    HStack(spacing: 7) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text("直播中").font(BeansFont.appFont(12, .semibold))
                        Text(room.viewers).font(BeansFont.appFont(12))
                        Spacer()
                        Button {
                            pausedForChild = true
                            video.pause()
                            navigation.push(.up(room.owner))
                        } label: {
                            Image(systemName: "person.crop.circle").font(.system(size: 18, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开主播主页")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(room.title)
                        .font(BeansFont.appFont(19, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(3)
                    Button {
                        pausedForChild = true
                        video.pause()
                        navigation.push(.up(room.owner))
                    } label: {
                        HStack(spacing: 11) {
                            CoverImage(url: room.owner.coverURL, size: 42, cornerRadius: 21)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(room.owner.name).font(BeansFont.appFont(15, .semibold))
                                Text("主播主页 · 进入直播间动态").font(BeansFont.appFont(12)).foregroundStyle(Color.beansComment)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.beansComment)
                        }
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 8) {
                        liveMetric("眼睛", room.viewers)
                        liveMetric("状态", "直播中")
                        Spacer()
                        Button { play() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                            .font(BeansFont.appFont(12, .medium))
                            .buttonStyle(.bordered)
                    }
                    Picker("直播内容", selection: $tab) {
                        Text("直播间").tag(0)
                        Text("简介").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if tab == 0 {
                        livePanel(title: "互动区", icon: "message", text: "进入直播间后可查看实时互动内容")
                        livePanel(title: "直播信息", icon: "info.circle", text: "直播画面、主播资料和状态会随直播间实时更新")
                    } else {
                        livePanel(title: "关于本场直播", icon: "text.alignleft", text: "这是一个哔哩哔哩直播间。直播结束后，播放地址可能暂时不可用。")
                    }
                }
                .padding(16)
            }
            .padding(.bottom, 150)
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

    private func liveMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(BeansFont.appFont(11)).foregroundStyle(Color.beansComment)
            Text(value).font(BeansFont.appFont(12, .medium)).foregroundStyle(Color.beansLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.beansGlassFill, in: Capsule())
    }

    private func livePanel(title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color(red: 0.96, green: 0.31, blue: 0.50))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(BeansFont.appFont(14, .semibold)).foregroundStyle(Color.beansLabel)
                Text(text).font(BeansFont.appFont(12)).foregroundStyle(Color.beansComment)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Color.beansGlassFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

