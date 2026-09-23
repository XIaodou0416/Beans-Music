import SwiftUI
import Combine

struct SongCell: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthStore
    @State private var downloadProgress: SongDownloadProgress?
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @AppStorage("beans.showSongVIPBadge") private var showSongVIPBadge = true
    @AppStorage(ThirdPartyAudioQuality.downloadStorageKey) private var downloadQualityRaw = ThirdPartyAudioQuality.kb320.rawValue
    @AppStorage(BeansBackendSettings.downloadUnlockKey) private var downloadFeatureUnlocked = false

    let song: Song
    var showCover = true
    /// 玻璃行模式：为行添加清透液态玻璃底（二级列表页统一风格用）
    var glassRow = false
    /// 需要整体玻璃容器时，单行保持纯净背景
    var suppressNativeCleanRowGlass = false
    /// 专辑详情使用紧凑的编号曲目行，保留原有点击、菜单及下载能力。
    var leadingIndex: Int?
    var compactAlbumRow = false
    /// 覆盖默认封面与行高，用于排行榜等紧凑但需要大封面的列表。
    var coverSize: CGFloat = 46
    var fixedRowHeight: CGFloat?
    var playbackContext: [Song] = []
    var playbackIndex: Int?
    var onTap: (() -> Void)?

    @State private var showAddToPlaylist = false
    @State private var shareFile: ShareFileItem?
    @State private var appeared = false

    private var isCurrent: Bool {
        player.currentSong?.identityKey == song.identityKey
    }

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if let leadingIndex {
                // Keep the track number stable. Showing a second waveform
                // here as well as at the trailing edge made album/detail rows
                // jump between two different leading layouts on older iOS.
                Text("\(leadingIndex)")
                    .font(BeansFont.appFont(12, .regular, .monospaced))
                    .foregroundStyle(Color.beansComment)
                    .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
            }
            if showCover {
                CoverImage(url: song.coverURL, song: song, size: coverSize, cornerRadius: 10)
            }
            VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(song.name)
                            .font(BeansFont.appFont(15, isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? Color.beansAmber : Color.beansLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        if showSongVIPBadge, song.isVIP {
                            VIPBadgeView(text: "VIP")
                        }
                    }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text(song.artists.isEmpty ? "未知歌手" : song.artists)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if let download = downloadProgress {
                VStack(spacing: 3) {
                    if let fraction = download.fractionCompleted {
                        ProgressView(value: fraction)
                            .tint(Color.beansAmber)
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(BeansFont.appFont(10, .medium, .monospaced))
                            .foregroundStyle(Color.beansComment)
                            .monospacedDigit()
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.beansAmber)
                    }
                }
                .frame(width: 46, height: 32)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("正在下载 \(download.title)")
            } else if isCurrent && player.isPlaying {
                NowPlayingIndicator()
            } else {
                Text(song.formattedDuration)
                    .font(BeansFont.appFont(12, .regular, .monospaced))
                    .foregroundStyle(Color.beansComment)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, leadingIndex == nil ? 0 : 16)
        .padding(.vertical, 6)
        .frame(height: fixedRowHeight ?? (compactAlbumRow ? 54 : nil))
        .contentShape(Rectangle())
        .scaleEffect(isCurrent ? 1.012 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isCurrent)
        .onTapGesture {
            onTap?()
        }
        .onReceive(DownloadManager.shared.$songProgress
            .map { $0[song.identityKey] }
            .removeDuplicates()) { downloadProgress = $0 }
        .contextMenu {
            Button {
                player.playNext(song)
            } label: {
                Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                showAddToPlaylist = true
            } label: {
                Label("添加到歌单", systemImage: "text.badge.plus")
            }
            if downloadFeatureUnlocked {
                Button {
                    Task { await downloadSong() }
                } label: {
                    Label("下载歌曲", systemImage: "arrow.down.circle")
                }
                .disabled(downloadProgress != nil)
            }
            if !isCurrent {
                Button {
                    if let playbackIndex, !playbackContext.isEmpty {
                        player.play(songs: playbackContext, startAt: playbackIndex)
                    } else if let index = player.queue.firstIndex(of: song) {
                        player.playQueueIndex(index)
                    } else {
                        player.play(songs: [song], startAt: 0)
                    }
                } label: {
                    Label("立即播放", systemImage: "play.fill")
                }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToLocalPlaylistSheet(song: song)
                .environmentObject(theme)
        }
        .sheet(item: $shareFile) { item in
            ShareSheet(items: [item.url])
        }
    }

    @MainActor
    private func downloadSong() async {
        let quality: DownloadQuality
        if UserDefaults.standard.object(forKey: ThirdPartyAudioQuality.downloadStorageKey) == nil {
            quality = ThirdPartyAudioQuality.current
        } else {
            quality = DownloadQuality(sourceValue: downloadQualityRaw) ?? ThirdPartyAudioQuality.current
        }
        BeansHaptics.medium()
        ToastCenter.shared.show("开始下载：\(song.name)（\(quality.displayName)）")
        let result = await DownloadManager.shared.download(song: song, quality: quality)
        switch result {
        case .success(let downloaded):
            if downloaded.downgraded {
                ToastCenter.shared.show("目标音质不可用，已降级为 \(downloaded.actualQuality.displayName)", duration: 3)
            }
            shareFile = ShareFileItem(url: downloaded.url)
        case .failure(let error):
            ToastCenter.shared.show("下载失败：\(error.localizedDescription)", duration: 3)
        }
    }

    var body: some View {
        let _ = theme.accent
        Group {
        if glassRow || (isNativeClean && !suppressNativeCleanRowGlass) {
                rowContent
                    .padding(.horizontal, 10)
                    .background {
                                            BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
            } else {
                rowContent
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.28), value: appeared)
        .onAppear { appeared = true }
    }
}
