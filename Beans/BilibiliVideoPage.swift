import SwiftUI
import AVFoundation
import UIKit

// Adapted from CiliCili's GPL-3.0 video-detail composition.
struct BilibiliVideoPage: View {
    let song: Song
    @EnvironmentObject private var music: PlayerManager
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @Environment(\.dismiss) private var dismiss
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
    @State private var showCommentComposer = false
    @State private var commentsRefresh = 0
    @State private var loadingDetail = false
    @State private var started = false
    @State private var resumeAfterChild = false
    @State private var presentingChild = false
    @State private var routeDepth = 0
    @AppStorage("beans.bilibili.autoPlayEnabled") private var autoPlayEnabled = true

    private let ciliPink = Color(red: 0.98, green: 0.31, blue: 0.53)

    var body: some View {
        GeometryReader { geometry in
            let playerHeight = min(geometry.size.width * 9.0 / 16.0, geometry.size.height * 0.72)
            ZStack(alignment: .top) {
                detailTabContent(playerHeight: playerHeight)
                    .zIndex(0)
                playback
                    .frame(maxWidth: .infinity)
                    .frame(height: playerHeight)
                    .clipped()
                    .zIndex(1)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { detailTabs }
        .task(id: song.identityKey) {
            BilibiliDetailDiagnostics.record("video page task: \(song.identityKey)")
            if !started {
                started = true
                routeDepth = navigation.path.count
                selectedPart = song
                music.pauseForBilibiliVideo()
                if autoPlayEnabled { play() }
            }
            if detail == nil { await load() }
        }
        .onAppear {
            BilibiliPresentationState.shared.enterVideo(song.identityKey)
            resumeFromChildIfNeeded()
        }
        .onDisappear {
            BilibiliDetailDiagnostics.record("video page disappear: \(song.identityKey)")
            BilibiliPresentationState.shared.leaveVideo(song.identityKey)
            rememberPosition()
            if !showFullscreenPlayer {
                if navigation.path.count > routeDepth {
                    pauseForChild()
                } else {
                    videoPlayer.stop()
                }
            }
        }
        .onChange(of: navigation.path.count) { count in
            if count <= routeDepth { resumeFromChildIfNeeded() }
        }
        .onChange(of: quality) { _ in
            rememberPosition()
            play(force: true)
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
        .fullScreenCover(isPresented: $showFullscreenPlayer, onDismiss: leaveFullscreen) {
            BilibiliFullscreenPlayer(model: videoPlayer, quality: $quality, onDismiss: {
                rememberPosition()
                showFullscreenPlayer = false
            }, onRetry: { play(force: true) })
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

    @ViewBuilder
    private func detailTabContent(playerHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                .padding(.bottom, 12)
            }
            .refreshable { await load() }
            .opacity(tab == 0 ? 1 : 0)
            .allowsHitTesting(tab == 0)
            .accessibilityHidden(tab != 0)

            if let detail {
                BilibiliNativeComments(
                    aid: detail.aid,
                    showsComposerBar: false,
                    composer: $showCommentComposer,
                    refreshID: commentsRefresh,
                    isActive: tab == 1
                )
                .environment(\.bilibiliNavigate, navigate)
                .opacity(tab == 1 ? 1 : 0)
                .allowsHitTesting(tab == 1)
                .accessibilityHidden(tab != 1)
            }
        }
        // Both scrolling viewports begin below the same fixed player surface.
        // Neither the tab selection nor scrolling can change this inset.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .padding(.top, playerHeight)
        .animation(.easeOut(duration: 0.22), value: tab)
    }

    private var playback: some View {
        BilibiliDetailVideoSurface(model: videoPlayer, quality: $quality, onBack: closePage, onExpand: enterFullscreen, onRetry: { play(force: true) }, onSettings: { showPlaybackSettings = true })
        .background(Color.black)
    }

    private func detailContent(_ info: BilibiliVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button { expanded.toggle() } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(info.song.name).font(.system(size: 22, weight: .bold)).foregroundStyle(.primary)
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
                }.font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                if expanded && !info.description.isEmpty {
                    Text(info.description).font(.system(size: 15)).foregroundStyle(.secondary)
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
                                guard selectedPart?.identityKey != part.identityKey else { return }
                                savedProgress = 0
                                selectedPart = part
                                play()
                            } label: {
                                Text("P\(index + 1) · \(part.name)").font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(selectedPart?.identityKey == part.identityKey ? ciliPink : .primary)
                                    .lineLimit(1).padding(.horizontal, 13).padding(.vertical, 10)
                                    .background(Color.beansGlassFill, in: Capsule())
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
    }

    private func actionStrip(_ info: BilibiliVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(info.owner.name) { navigate(.up(info.owner)) }
                .font(.subheadline.weight(.semibold)).lineLimit(1).buttonStyle(.plain)
            // CiliCili uses six equal-width columns instead of fixed button
            // widths. This also keeps the strip inside narrow phone margins.
            HStack(spacing: 7) {
                Button { navigate(.up(info.owner)) } label: {
                    CoverImage(url: info.owner.coverURL, size: 34, cornerRadius: 17)
                }.buttonStyle(.plain).frame(maxWidth: .infinity)
                Button { followOwner(info.owner) } label: {
                    Text(following == true ? "已关注" : "关注")
                        .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(.white).padding(.horizontal, 6).frame(height: 28)
                        .background(ciliPink, in: Capsule())
                }.buttonStyle(.plain).disabled(followingBusy).frame(maxWidth: .infinity)
                detailAction("hand.thumbsup.fill", "点赞", selected: interaction?.liked == true) { like() }
                detailAction("bitcoinsign.circle.fill", "投币", selected: (interaction?.coins ?? 0) > 0) {
                    if account.isLoggedIn { showCoins = true } else { showLogin = true }
                }
                detailAction("star.fill", "收藏", selected: interaction?.favorited == true) {
                    if account.isLoggedIn { showFavorites = true } else { showLogin = true }
                }
                detailAction("square.and.arrow.up", "分享", selected: false) { share = true }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailAction(_ icon: String, _ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? ciliPink : .primary).frame(width: 32, height: 32)
                .background { BeansGlass(shape: Circle(), forceLiquid: true) }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(title)
        .frame(maxWidth: .infinity)
    }

    private var detailTabs: some View {
        HStack(spacing: 10) {
            if tab == 1 {
                Button { commentsRefresh += 1 } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .background { BeansGlass(shape: Circle(), forceLiquid: true) }
                .accessibilityLabel("刷新评论")
                .disabled(detail == nil)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            HStack(spacing: 0) {
                Button("简介") { tab = 0 }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tab == 0 ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                    .accessibilityAddTraits(tab == 0 ? .isSelected : [])
                Button("评论") { tab = 1 }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tab == 1 ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                    .accessibilityAddTraits(tab == 1 ? .isSelected : [])
                    .disabled(detail == nil)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(4)
            .frame(maxWidth: 144)
            .frame(height: 40)
            .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)

            if tab == 1 {
                Button { showCommentComposer = true } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .background { BeansGlass(shape: Circle(), forceLiquid: true) }
                .accessibilityLabel("发表评论")
                .disabled(detail == nil)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .frame(maxWidth: 430)
        .frame(height: 64)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .zIndex(20)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.primary)
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 12)
    }

    private func closePage() {
        BeansDiagnostics.shared.recordAction("关闭哔哩哔哩视频详情")
        rememberPosition()
        videoPlayer.stop()
        if routeDepth > 0 {
            navigation.pop(to: routeDepth - 1)
        } else {
            dismiss()
        }
    }

    private func rememberPosition() {
        if let seconds = videoPlayer.player?.currentTime().seconds, seconds.isFinite { savedProgress = seconds }
    }

    private func enterFullscreen() {
        BeansDiagnostics.shared.recordAction("哔哩哔哩视频进入横屏播放")
        rememberPosition()
        showFullscreenPlayer = true
        requestOrientation(.landscapeRight)
    }

    private func leaveFullscreen() {
        requestOrientation(.portrait)
    }

    private func requestOrientation(_ orientation: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
    }

    private func play(force: Bool = false) {
        let part = selectedPart ?? song
        let requestedQuality = quality
        music.pauseForBilibiliVideo()
        videoPlayer.open(key: "\(part.identityKey)|\(requestedQuality)", force: force, resumeAt: savedProgress) {
            try await BilibiliAPI.shared.nativeVideoURLs(part, quality: requestedQuality)
        }
    }

    private func navigate(_ route: BilibiliNativeRoute) {
        BeansDiagnostics.shared.recordAction("详情页导航：\(route)")
        pauseForChild()
        navigation.push(route)
    }

    private func pauseForChild() {
        guard !presentingChild else { return }
        presentingChild = true
        resumeAfterChild = videoPlayer.wantsPlayback
        rememberPosition()
        videoPlayer.pause()
    }

    private func resumeFromChildIfNeeded() {
        guard presentingChild, navigation.path.count <= routeDepth else { return }
        presentingChild = false
        if resumeAfterChild { videoPlayer.resume() }
        resumeAfterChild = false
    }

    private func load() async {
        guard !loadingDetail else { return }
        loadingDetail = true
        defer { loadingDetail = false }
        loadError = nil
        do {
            let result = try await BilibiliAPI.shared.nativeVideo(song)
            try Task.checkCancellation()
            detail = result
            await updateInteraction()
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
        if let detail, let videos = try? await BilibiliAPI.shared.relatedVideos(aid: detail.aid) {
            guard !Task.isCancelled else { return }
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
                Text(item.song.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(item.song.artists).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                if item.playCount > 0 {
                    Label(BilibiliFeedVideo.countLabel(item.playCount), systemImage: "play.fill")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
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
    let onRetry: () -> Void

    var body: some View {
        GeometryReader { geometry in
            BilibiliDetailVideoSurface(model: model, quality: $quality, onBack: onDismiss, onExpand: onDismiss, onRetry: onRetry)
                .frame(width: geometry.size.width, height: geometry.size.height).background(Color.black).ignoresSafeArea()
        }
        .background(Color.black).statusBarHidden(true)
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

