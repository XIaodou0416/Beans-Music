import SwiftUI

/// 已解锁下载权限时，顺序下载列表中的歌曲到应用本地下载目录，并允许完成后分享。
struct BatchDownloadSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloader = BatchDownloadManager.shared
    @ObservedObject private var transfers = DownloadManager.shared

    let songs: [Song]
    let title: String

    @State private var selectedQuality: DownloadQuality
    @State private var showShareSheet = false

    init(songs: [Song], title: String = "批量下载") {
        self.songs = songs
        self.title = title
        let stored = UserDefaults.standard.string(forKey: ThirdPartyAudioQuality.downloadStorageKey)
        _selectedQuality = State(
            initialValue: DownloadQuality(sourceValue: stored ?? "") ?? ThirdPartyAudioQuality.current
        )
    }

    private var uniqueSongCount: Int {
        Set(songs.map(\.identityKey)).count
    }

    var body: some View {
        BeansNavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Color.beansAmber)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("下载 \(uniqueSongCount) 首歌曲")
                                .font(BeansFont.appFont(16, .semibold))
                                .foregroundStyle(Color.beansLabel)
                            Text("按顺序下载并保存在本地，可在完成后一次性分享")
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if downloader.isDownloading || downloader.totalCount > 0 {
                    Section("下载进度") {
                        VStack(alignment: .leading, spacing: 10) {
                            ProgressView(value: downloader.progress)
                                .tint(Color.beansAmber)
                            HStack {
                                Text(downloader.statusText)
                                Spacer()
                                Text("\(Int((downloader.progress * 100).rounded()))%")
                            }
                            .font(BeansFont.appFont(12, .medium))
                            .foregroundStyle(Color.beansComment)
                            if !downloader.currentSongName.isEmpty {
                                Text(downloader.currentSongName)
                                    .font(BeansFont.appFont(13))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(1)
                            }
                            if let transfer = transfers.songProgress[downloader.currentSongKey] {
                                if let fraction = transfer.fractionCompleted {
                                    ProgressView(value: fraction)
                                        .tint(Color.beansAmber)
                                    Text("当前歌曲 \(Int((fraction * 100).rounded()))%")
                                        .font(BeansFont.appFont(12, .medium))
                                        .foregroundStyle(Color.beansComment)
                                        .monospacedDigit()
                                } else {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("正在获取歌曲…")
                                            .font(BeansFont.appFont(12))
                                            .foregroundStyle(Color.beansComment)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        if downloader.isDownloading {
                            Button(role: .destructive) {
                                downloader.cancel()
                            } label: {
                                Label("取消下载", systemImage: "xmark.circle")
                            }
                        } else if !downloader.downloadedFiles.isEmpty {
                            Button {
                                showShareSheet = true
                            } label: {
                                Label("分享已下载歌曲（\(downloader.downloadedFiles.count)）", systemImage: "square.and.arrow.up")
                            }
                        }

                        if !downloader.failedSongs.isEmpty {
                            Text("未完成：\(downloader.failedSongs.prefix(5).joined(separator: "、"))\(downloader.failedSongs.count > 5 ? "等" : "")")
                                .font(BeansFont.appFont(11))
                                .foregroundStyle(Color.beansComment)
                                .lineLimit(2)
                        }
                    }
                }

                Section("下载音质") {
                    Picker("下载音质", selection: $selectedQuality) {
                        ForEach(DownloadQuality.allCases, id: \.rawValue) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    .disabled(downloader.isDownloading)
                }

                Section {
                    Button {
                        UserDefaults.standard.set(selectedQuality.rawValue, forKey: ThirdPartyAudioQuality.downloadStorageKey)
                        BeansHaptics.medium()
                        downloader.start(songs: songs, quality: selectedQuality)
                    } label: {
                        Label(
                            downloader.totalCount > 0 && !downloader.isDownloading ? "重新批量下载" : "开始批量下载",
                            systemImage: "arrow.down.to.line.compact"
                        )
                    }
                    .disabled(uniqueSongCount == 0 || downloader.isDownloading)
                }
            }
            .beansScrollContentBackgroundHidden()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: downloader.downloadedFiles)
        }
        .onDisappear {
            if downloader.isDownloading {
                downloader.cancel()
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
    }
}
