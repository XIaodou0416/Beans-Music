import SwiftUI
import AVFoundation

// Adapted from CiliCili's GPL-3.0 video-detail composition.
struct BilibiliVideoPage: View {
    let song: Song
    @EnvironmentObject private var music: PlayerManager
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bilibiliDismissVideo) private var dismissVideo
    @StateObject private var videoPlayer = BilibiliNativePlayer()
    @ObservedObject private var account = BilibiliAuth.shared
    @State private var detail: BilibiliVideoInfo?
    @State private var loadError: String?
    @State private var tab = 0
    @State private var quality = 64
    @State private var selectedPart: Song?
    @State private var expanded = false
    @State private var showLogin = false
    @State private var showCoins = false
    @State private var showFavorites = false
    @State private var interaction: BilibiliInteractionState?
    @State private var relatedVideos: [BilibiliFeedVideo] = []
    @State private var busy = false
    @State private var following: Bool?
    @State private var followingBusy = false
    @State private var message: String?
    @State private var share = false
    @State private var savedProgress = 0.0
    @State private var showFullscreenPlayer = false
    @State private var showPlaybackSettings = false
    @State private var presentingChild = false
    @State private var routeDepth = 0

    private let ciliPink = Color(red: 0.98, green: 0.31, blue: 0.53)

    var body: some View {
        Group {
            if tab == 1, let detail {
                VStack(spacing: 0) {
                    playback
                    BilibiliNativeComments(aid: detail.aid)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { detailTabs }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        playback
                        if let detail {
                            detailContent(detail)
                        } else if let loadError {
                            BilibiliInlineError(message: loadError) { Task { await load() } }
                                .padding(24)
                        } else {
                            ProgressView("加载视频信息")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        }
                    }
                    .padding(.bottom, 92)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { detailTabs }
            }
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: closePage) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 42, height: 42)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 1))
                }
                .accessibilityLabel("返回")
            }
        }
        .background { BilibiliVideoTabBarHider() }
        .task(id: song.identityKey) {
            BilibiliDetailDiagnostics.record("video page task: \(song.identityKey)")
            BilibiliPresentationState.shared.enterVideo(song.identityKey)
            routeDepth = navigation.path.count
            music.pauseForBilibiliVideo()
            if selectedPart == nil { selectedPart = song }
            if !presentingChild { play() }
            if detail == nil { await load() }
        }
        .onDisappear {
            BilibiliDetailDiagnostics.record("video page disappear: \(song.identityKey)")
            BilibiliPresentationState.shared.leaveVideo(song.identityKey)
            rememberPosition()
            if !presentingChild && !showFullscreenPlayer { videoPlayer.stop() }
        }
        .onChange(of: navigation.path.count) { count in
            if presentingChild && count <= routeDepth {
                presentingChild = false
                videoPlayer.player?.play()
            }
        }
        .onChange(of: quality) { _ in
            guard !showFullscreenPlayer else { return }
            rememberPosition()
            play()
        }
        .onReceive(NotificationCenter.default.publisher(for: .beansBilibiliLoginDidUpdate)) { _ in
            Task { await updateInteraction() }
        }
        .sheet(isPresented: $showLogin) { BilibiliLoginSheet() }
        .sheet(isPresented: $showFavorites) {
            if let detail {
                BilibiliFavoritePicker(aid: detail.aid) { Task { await updateInteraction() } }
            }
        }
        .sheet(isPresented: $showPlaybackSettings) {
            BilibiliPlaybackSettings(quality: $quality)
        }
        .sheet(isPresented: $share) {
            if let url = song.officialURL { ShareSheet(items: [url]) }
        }
        .fullScreenCover(isPresented: $showFullscreenPlayer) {
            BilibiliFullscreenPlayer(model: videoPlayer, quality: $quality, onDismiss: {
                rememberPosition()
                showFullscreenPlayer = false
                videoPlayer.player?.play()
            }, onQualityChanged: {
                rememberPosition()
                play()
            })
            .onAppear { videoPlayer.player?.play() }
        }
        .confirmationDialog("选择投币数量", isPresented: $showCoins, titleVisibility: .visible) {
            Button("投 1 枚硬币") { coin(1) }
            Button("投 2 枚硬币") { coin(2) }
            Button("取消", role: .cancel) {}
        } message: { Text("将消耗当前 B 站账号的硬币，投币后不能撤回。") }
        .alert("操作提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
    }

    private var playback: some View {
        BilibiliDetailVideoSurface(model: videoPlayer, quality: $quality, onBack: closePage, onExpand: {
            rememberPosition()
            showFullscreenPlayer = true
        }, onSettings: { showPlaybackSettings = true })
        .background(Color.black)
    }

    private func detailContent(_ info: BilibiliVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button { expanded.toggle() } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(info.song.name).font(.system(size: 22, weight: .bold)).foregroundStyle(.black)
                            .lineLimit(expanded ? nil : 2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.gray).padding(.top, 4)
                    }
                }.buttonStyle(.plain)
                HStack(spacing: 10) {
                    Text("\(BilibiliFeedVideo.countLabel(info.views)) 次播放")
                    Text("·")
                    Text(info.published.formatted(date: .abbreviated, time: .omitted))
                }.font(.system(size: 14, weight: .medium)).foregroundStyle(Color.gray)
                if expanded && !info.description.isEmpty {
                    Text(info.description).font(.system(size: 15)).foregroundStyle(Color.gray)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }.padding(.horizontal, 28).padding(.top, 22)

            actionStrip(info).padding(.horizontal, 28).padding(.top, 18)
            if busy { ProgressView().frame(maxWidth: .infinity).padding(.top, 8) }

            if info.parts.count > 1 {
                sectionTitle("分集")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(info.parts.enumerated()), id: \.element.identityKey) { index, part in
                            Button {
                                savedProgress = 0
                                selectedPart = part
                                play()
                            } label: {
                                Text("P\(index + 1) · \(part.name)").font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(selectedPart?.identityKey == part.identityKey ? ciliPink : .black)
                                    .lineLimit(1).padding(.horizontal, 13).padding(.vertical, 10)
                                    .background(Color(white: 0.95), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 28)
                }.padding(.top, 2)
            }

            if let collection = info.collection {
                sectionTitle("所属合集")
                Button { navigate(.collection(collection)) } label: {
                    BilibiliCollectionRow(collection: collection).padding(.horizontal, 28)
                }.buttonStyle(.plain)
            }

            if !relatedVideos.isEmpty {
                sectionTitle("相关推荐")
                LazyVStack(spacing: 0) {
                    ForEach(relatedVideos) { item in
                        Button { navigate(.video(item.song)) } label: { CiliCiliRelatedRow(item: item) }
                            .buttonStyle(.plain)
                        Divider().padding(.leading, 188)
                    }
                }.padding(.horizontal, 28)
            }
        }
        .refreshable { await load() }
    }

    private func actionStrip(_ info: BilibiliVideoInfo) -> some View {
        HStack(spacing: 8) {
            Button { navigate(.up(info.owner)) } label: {
                CoverImage(url: info.owner.coverURL, size: 38, cornerRadius: 19).frame(width: 48, height: 42)
            }.buttonStyle(.plain)
            Button { followOwner(info.owner) } label: {
                Text(following == true ? "已关注" : "关注").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white).frame(width: 70, height: 36).background(ciliPink, in: Capsule())
            }.buttonStyle(.plain).disabled(followingBusy)
            detailAction("hand.thumbsup.fill", "点赞", selected: interaction?.liked == true) { like() }
            detailAction("bitcoinsign.circle.fill", "投币", selected: (interaction?.coins ?? 0) > 0) {
                if account.isLoggedIn { showCoins = true } else { showLogin = true }
            }
            detailAction("star.fill", "收藏", selected: interaction?.favorited == true) {
                if account.isLoggedIn { showFavorites = true } else { showLogin = true }
            }
            detailAction("square.and.arrow.up", "分享", selected: false) { share = true }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailAction(_ icon: String, _ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }.foregroundStyle(selected ? ciliPink : .black).frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .background { BeansGlass(shape: Circle(), forceLiquid: true) }
    }

    private var detailTabs: some View {
        HStack(spacing: 0) {
            Button("简介") { tab = 0 }.frame(maxWidth: .infinity)
            Button("评论") { tab = 1 }.frame(maxWidth: .infinity)
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.black)
        .frame(width: 270, height: 52)
        .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.bottom, 10)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.black)
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 12)
    }

    private func closePage() {
        if routeDepth > 0 {
            navigation.pop(to: routeDepth - 1)
        } else if let dismissVideo {
            dismissVideo()
        } else {
            dismiss()
        }
    }

    private func rememberPosition() {
        if let seconds = videoPlayer.player?.currentTime().seconds, seconds.isFinite { savedProgress = seconds }
    }

    private func play() {
        let part = selectedPart ?? song
        music.pauseForBilibiliVideo()
        videoPlayer.open(resumeAt: savedProgress) { try await BilibiliAPI.shared.nativeVideoURLs(part, quality: quality) }
    }

    private func navigate(_ route: BilibiliNativeRoute) {
        presentingChild = true
        rememberPosition()
        videoPlayer.pause()
        navigation.push(route)
    }

    private func load() async {
        loadError = nil
        do {
            detail = try await BilibiliAPI.shared.nativeVideo(song)
            await updateInteraction()
        } catch { loadError = error.localizedDescription }
        if let detail, let videos = try? await BilibiliAPI.shared.relatedVideos(aid: detail.aid) {
            relatedVideos = videos.filter { $0.song.identityKey != song.identityKey }
        }
    }

    private func updateInteraction() async {
        guard account.isLoggedIn, let detail else { interaction = nil; following = nil; return }
        interaction = try? await BilibiliAPI.shared.nativeInteraction(aid: detail.aid)
        if let profile = try? await BilibiliAPI.shared.upProfile(detail.owner.id) {
            following = profile.following
        } else {
            following = nil
        }
    }

    private func like() {
        guard account.isLoggedIn else { showLogin = true; return }
        guard let detail, let interaction, !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await BilibiliAPI.shared.nativeLike(aid: detail.aid, liked: !interaction.liked)
                self.interaction?.liked.toggle()
            } catch { message = error.localizedDescription; await updateInteraction() }
        }
    }

    private func coin(_ count: Int) {
        guard let detail, !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await BilibiliAPI.shared.nativeCoin(aid: detail.aid, count: count); message = "投币成功" }
            catch { message = "\(error.localizedDescription)。请刷新确认结果，勿重复投币。" }
            await updateInteraction()
        }
    }

    private func followOwner(_ owner: Artist) {
        guard account.isLoggedIn else { showLogin = true; return }
        guard !followingBusy else { return }
        followingBusy = true
        Task { @MainActor in
            defer { followingBusy = false }
            do {
                let current: Bool
                if let following {
                    current = following
                } else {
                    current = try await BilibiliAPI.shared.upProfile(owner.id).following
                }
                try await BilibiliAPI.shared.nativeFollow(id: owner.id, follow: !current)
                following = !current
            } catch { message = error.localizedDescription }
        }
    }
}

private struct CiliCiliRelatedRow: View {
    let item: BilibiliFeedVideo
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: item.song.coverURL, size: 88, aspectRatio: 16.0 / 9.0, cornerRadius: 9)
                .frame(width: 148, height: 84)
                .overlay(alignment: .bottomTrailing) {
                    Text(item.song.formattedDuration).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 3)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4)).padding(5)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.song.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(item.song.artists).font(.system(size: 13)).foregroundStyle(.gray).lineLimit(1)
                if item.playCount > 0 {
                    Label(BilibiliFeedVideo.countLabel(item.playCount), systemImage: "play.fill")
                        .font(.system(size: 12)).foregroundStyle(.gray)
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 12).contentShape(Rectangle())
    }
}

private struct BilibiliFullscreenPlayer: View {
    @ObservedObject var model: BilibiliNativePlayer
    @Binding var quality: Int
    let onDismiss: () -> Void
    let onQualityChanged: () -> Void
    @State private var lastQuality: Int

    init(model: BilibiliNativePlayer, quality: Binding<Int>, onDismiss: @escaping () -> Void, onQualityChanged: @escaping () -> Void) {
        self.model = model
        _quality = quality
        self.onDismiss = onDismiss
        self.onQualityChanged = onQualityChanged
        _lastQuality = State(initialValue: quality.wrappedValue)
    }

    var body: some View {
        GeometryReader { geometry in
            BilibiliDetailVideoSurface(model: model, quality: $quality, onBack: onDismiss, onExpand: {})
                .frame(width: geometry.size.width, height: geometry.size.height).background(Color.black).ignoresSafeArea()
        }
        .background(Color.black).statusBarHidden(true)
        .onChange(of: quality) { value in
            guard value != lastQuality else { return }
            lastQuality = value
            onQualityChanged()
        }
    }
}

struct BilibiliFavoritePicker: View {
    let aid: String
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [BilibiliFavoriteFolder] = []
    @State private var selected = Set<String>()
    @State private var original = Set<String>()
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        BeansNavigationStack {
            List {
                if loading { ProgressView("加载收藏夹") }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                    Button("重新加载") { Task { await load() } }
                }
                ForEach(folders) { folder in
                    Button {
                        if selected.contains(folder.id) { selected.remove(folder.id) } else { selected.insert(folder.id) }
                    } label: {
                        HStack {
                            Text(folder.title).foregroundStyle(Color.beansLabel)
                            Spacer()
                            Image(systemName: selected.contains(folder.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }.disabled(saving)
                }
                if !loading && folders.isEmpty && error == nil { Text("账号还没有收藏夹") }
            }
            .navigationTitle("选择收藏夹").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") {
                        saving = true
                        error = nil
                        Task { @MainActor in
                            defer { saving = false }
                            do {
                                try await BilibiliAPI.shared.nativeFavorite(aid: aid, add: selected.subtracting(original), remove: original.subtracting(selected))
                                onSaved(); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(loading || saving || folders.isEmpty)
                }
            }
        }.task { await load() }.interactiveDismissDisabled(saving)
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            folders = try await BilibiliAPI.shared.nativeFolders(aid: aid)
            original = Set(folders.filter(\.containsVideo).map(\.id))
            selected = original
        } catch { self.error = error.localizedDescription }
    }
}

