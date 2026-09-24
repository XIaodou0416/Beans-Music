import SwiftUI

struct MinePlaybackToolsSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("播放工具") {
            Toggle(
                isOn: Binding(
                    get: { libraryStore.sponsorBlockEnabled },
                    set: { libraryStore.setSponsorBlockEnabled($0) }
                )
            ) {
                MineSettingsLabel("空降助手", systemImage: "forward.end")
            }

            NavigationLink {
                ResourceLoadingExperimentSettingsView(libraryStore: libraryStore)
            } label: {
                PlainSettingsNavigationRow(
                    title: "资源加载调度",
                    subtitle: "4 项正式启用，1 项仍可独立调整",
                )
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.playerPerformanceOverlayEnabled },
                    set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                )
            ) {
                MineSettingsLabel("播放性能诊断", systemImage: "waveform.path.ecg.rectangle")
            }

            NavigationLink {
                PlayerPerformanceLogView()
            } label: {
                PlainSettingsNavigationRow(
                    title: "启动链路性能日志",
                    subtitle: "首帧、准备和缓冲",
                )
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.playbackPlayableFallbackDeadlineExperimentEnabled },
                    set: { libraryStore.setPlaybackPlayableFallbackDeadlineExperimentEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    MineSettingsLabel("可播放降级限时实验", systemImage: "timer")
                    Text("已有可播放低档位后，完整取流最多再等待 650ms；超时直接开始播放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(PlaybackPerformanceTestVideo.fixedSamples.enumerated()), id: \.element.id) { index, video in
                NavigationLink {
                    PlaybackPerformanceTestVideoView(testVideo: video)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        MineSettingsLabel("测试视频 \(index + 1)", systemImage: "play.rectangle")
                        Text(video.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.videoRotationFrameReportOverlayEnabled },
                    set: { libraryStore.setVideoRotationFrameReportOverlayEnabled($0) }
                )
            ) {
                MineSettingsLabel("旋转帧报告", systemImage: "rotate.right")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled },
                    set: { isEnabled in
                        if isEnabled {
                            PlaybackDetailPerformanceMonitor.shared.clear()
                        }
                        libraryStore.setVideoDetailNavigationLatencyDiagnosticsEnabled(isEnabled)
                    }
                )
            ) {
                MineSettingsLabel("视频详情导航时延诊断", systemImage: "stopwatch")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.playerControlEdgeScrimEnabled },
                    set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                )
            ) {
                MineSettingsLabel("播放控件边缘遮罩", systemImage: "rectangle.dashed")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.showsVideoDetailNetworkDiagnosticsButton },
                    set: { libraryStore.setShowsVideoDetailNetworkDiagnosticsButton($0) }
                )
            ) {
                MineSettingsLabel("视频详情网络诊断", systemImage: "stethoscope")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.showsVideoDetailPinnedProgressBar },
                    set: { libraryStore.setShowsVideoDetailPinnedProgressBar($0) }
                )
            ) {
                MineSettingsLabel("视频窗口底部进度条", systemImage: "line.3.horizontal.decrease")
            }

            Picker(
                selection: Binding(
                    get: { libraryStore.videoListenPlaylistSortOrder },
                    set: { libraryStore.setVideoListenPlaylistSortOrder($0) }
                )
            ) {
                ForEach(VideoListenPlaylistSortOrder.allCases) { order in
                    MineSettingsLabel(order.title, systemImage: order.systemImage)
                        .tag(order)
                }
            } label: {
                MineSettingsLabel("听视频列表排序", systemImage: libraryStore.videoListenPlaylistSortOrder.systemImage)
            }
            .pickerStyle(.menu)

            NavigationLink {
                ResourceCacheManagementView()
            } label: {
                PlainSettingsNavigationRow(
                    title: "资源缓存",
                    subtitle: "图片、接口、视频分片缓存",
                )
            }
        }
    }
}
