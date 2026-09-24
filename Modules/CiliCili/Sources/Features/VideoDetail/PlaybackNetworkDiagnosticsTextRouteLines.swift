import Foundation

@MainActor
extension PlaybackNetworkDiagnosticsTextBuilder {
    func appendCDNLines(to lines: inout [String]) {
        lines.append("当前 CDN：\(libraryStore.effectivePlaybackCDNPreference.title)")
        lines.append("CDN 设置：\(libraryStore.playbackCDNPreference.title)")
        lines.append("网络协议：\(libraryStore.playbackNetworkAddressFamilyPreference.title)")
        lines.append("播放自动优化：\(libraryStore.playbackAutoOptimizationMode.title)")
        lines.append("视频 Host：\(variant?.videoURL?.host ?? "未获取")")
        lines.append("音频 Host：\(variant?.audioURL?.host ?? "未获取")")
        let compatibilityState = CellularBiliTrafficCompatibilityExperiment.RuntimeState(
            isEnabled: libraryStore.cellularBiliTrafficCompatibilityExperimentEnabled,
            isCellularNetwork: NetworkPathSnapshot.shared.usesCellular
        )
        let sourceDiagnostics = playerViewModel?.engineDiagnostics
        lines.append("B站定向流量兼容：\(compatibilityState.userFacingStatus)")
        lines.append("媒体域名归类：\(CellularBiliTrafficCompatibilityExperiment.sourceHostSummary(videoHost: sourceDiagnostics?.sourceVideoHost, audioHost: sourceDiagnostics?.sourceAudioHost))")
        if compatibilityState.isActive,
           CellularBiliTrafficCompatibilityExperiment.hasExternalMediaHost(
            videoHost: sourceDiagnostics?.sourceVideoHost,
            audioHost: sourceDiagnostics?.sourceAudioHost
           ) {
            lines.append("外部媒体线路：当前使用，可能是没有 B站候选或播放兜底；请以运营商账单为准。")
        }

        if let currentHostSnapshot {
            lines.append("当前 Host 历史：\(PlaybackNetworkDiagnosticFormat.playbackURLPreferenceSummary(currentHostSnapshot))")
        }
        if !playbackURLPreferenceSnapshots.isEmpty {
            lines.append("真实播放排行：")
            lines.append(contentsOf: playbackURLPreferenceSnapshots.prefix(6).map { snapshot in
                "  \(snapshot.host) · \(PlaybackNetworkDiagnosticFormat.playbackURLPreferenceSummary(snapshot))"
            })
        }
        if !hlsBridgeSourceSnapshots.isEmpty {
            lines.append("HLSBridge 线路：")
            lines.append(contentsOf: hlsBridgeSourceSnapshots.prefix(8).map { snapshot in
                "  #\(snapshot.order) \(snapshot.host) · \(PlaybackNetworkDiagnosticFormat.hlsBridgeSourceSummary(snapshot))"
            })
        }
    }

    func appendStreamLines(to lines: inout [String]) {
        lines.append("清晰度：\(variant?.title ?? "未选择")")
        lines.append("封装模式：\(PlaybackNetworkDiagnosticFormat.streamModeTitle(for: variant))")
        lines.append("编码：\(PlaybackNetworkDiagnosticFormat.nilIfEmpty(variant?.codec) ?? "未知")")
        lines.append("分辨率：\(PlaybackNetworkDiagnosticFormat.nilIfEmpty(variant?.resolution) ?? "未知")")
        lines.append("帧率：\(PlaybackNetworkDiagnosticFormat.frameRateTitle(for: variant))")
        lines.append("带宽：\(PlaybackNetworkDiagnosticFormat.bandwidthTitle(for: variant))")
    }

    func appendProbeLines(to lines: inout [String]) {
        guard let snapshot = libraryStore.playbackCDNProbeSnapshotForCurrentContext else { return }
        lines.append("测速时间：\(snapshot.probedAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("测速参考：\(snapshot.recommendedPreference?.title ?? "暂无参考")")
        lines.append("测速模式：\(snapshot.isWeakReferenceOnly ? "Host 裸探测弱参考" : "真实播放 URL 优先")")
        lines.append("测速是否过期：\(snapshot.isExpired(freshnessInterval: libraryStore.playbackCDNProbeRefreshInterval) ? "是" : "否")")
        if snapshot.isWeakReferenceOnly {
            lines.append("测速说明：403/959 表示 CDN 拒绝裸探测，不代表真实播放失败；弱参考不会更新自动推荐。")
        }
        lines.append("测速结果：")
        lines.append(contentsOf: snapshot.results.prefix(8).map { result in
            let status = result.httpStatusTitle ?? "无 HTTP"
            let elapsed = result.elapsedMilliseconds.map { "\($0) ms" } ?? "无耗时"
            let rewrite = result.hostWasRewritten ? "已重写 Host" : "未重写 Host"
            let weak = result.isWeakReference ? "弱参考" : "可推荐"
            return "  \(result.preference.title) · \(result.probeMode.title) · \(status) · \(elapsed) · \(rewrite) · \(weak) · \(result.userFacingStatus)"
        })
    }
}
