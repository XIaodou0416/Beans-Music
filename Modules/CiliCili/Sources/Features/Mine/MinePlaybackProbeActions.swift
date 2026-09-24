import Foundation

extension MinePlaybackSettingsView {
    func probePlaybackCDN() {
        startPlaybackCDNProbe(isAutomatic: false)
    }

    func refreshPlaybackCDNProbeIfNeeded() {
        guard playbackCDNProbeTask == nil else { return }
        guard libraryStore.needsPlaybackCDNProbeRefresh else { return }
        startPlaybackCDNProbe(isAutomatic: true)
    }

    func startPlaybackCDNProbe(isAutomatic: Bool) {
        guard !isProbingPlaybackCDN else { return }
        isProbingPlaybackCDN = true
        playbackCDNProbeMessage = isAutomatic ? "CDN 测速已过期，正在刷新 Host 连通性参考..." : "正在测试 CDN Host 连通性..."
        if !isAutomatic {
            playbackCDNProbeResults = []
        }

        playbackCDNProbeTask?.cancel()
        playbackCDNProbeTask = Task {
            let addressFamilyPreference = await MainActor.run {
                libraryStore.playbackNetworkAddressFamilyPreference
            }
            let snapshot = await PlaybackCDNProbeService.recommendedSnapshot(
                addressFamilyPreference: addressFamilyPreference
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                playbackCDNProbeResults = snapshot.results
                libraryStore.setPlaybackCDNProbeSnapshot(snapshot)
                if snapshot.isWeakReferenceOnly {
                    playbackCDNProbeMessage = "设置页没有当前播放地址，本次只做 Host 弱参考；403/959 不代表真实播放失败，也不会更新自动推荐。"
                } else if let preference = snapshot.recommendedPreference,
                   let elapsed = snapshot.result(for: preference)?.elapsedMilliseconds {
                    if !isAutomatic {
                        libraryStore.setPlaybackCDNPreference(preference)
                    }
                    playbackCDNProbeMessage = isAutomatic
                        ? "已自动刷新 CDN：\(preference.title)，\(elapsed) ms"
                        : "已推荐 \(preference.title)，\(elapsed) ms"
                } else {
                    playbackCDNProbeMessage = "未找到可用 CDN，已保留当前设置"
                }
                refreshPlaybackURLPreferenceSnapshots()
                isProbingPlaybackCDN = false
                playbackCDNProbeTask = nil
            }
        }
    }

    func refreshPlaybackURLPreferenceSnapshots() {
        playbackURLPreferenceSnapshots = PlaybackURLPreferenceStore.shared.rankedSnapshots(limit: 8)
    }
}
