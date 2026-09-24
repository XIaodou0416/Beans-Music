import Foundation

@MainActor
extension PlaybackNetworkDiagnosticsTextBuilder {
    func appendHeaderLines(to lines: inout [String]) {
        lines.append("播放器网络诊断")
        lines.append("视频：\(diagnosticsStore.videoTitle)")
        lines.append("BVID：\(diagnosticsStore.metricsID)")
    }

    func appendLoadingLines(to lines: inout [String]) {
        lines.append("视频详情耗时：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(diagnosticsStore.detailLoadElapsedMilliseconds))")
        lines.append("播放地址耗时：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(diagnosticsStore.playURLElapsedMilliseconds))")
        lines.append("相关推荐耗时：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(diagnosticsStore.relatedElapsedMilliseconds))")
        lines.append("取流来源：\(PlaybackNetworkDiagnosticFormat.playURLSourceTitle(diagnosticsStore.lastPlayURLSource))")
    }

    func appendResumeLines(to lines: inout [String]) {
        let resumeDiagnostics = diagnosticsStore.resumeDiagnostics
        lines.append("续播来源：\(resumeDiagnostics.sourceTitle)")
        lines.append("续播目标：\(PlaybackNetworkDiagnosticFormat.formattedResumeTime(resumeDiagnostics.targetTime))")
        lines.append("续播 CID：\(resumeDiagnostics.cid.map(String.init) ?? "未确定")")
        lines.append("续播状态：\(resumeDiagnostics.statusTitle)")
        lines.append("续播原因：\(resumeDiagnostics.reason)")
    }

    func appendBaselineLines(to lines: inout [String]) {
        lines.append("自适应等级：\(playbackAdaptationProfile.diagnosticTitle)")
        lines.append("启动清晰度上限：\(playbackAdaptationProfile.startupQualityCeilingTitle)")
        lines.append("后台预加载额度：\(playbackAdaptationProfile.backgroundPreloadLimit)")
        lines.append("弹幕负载：\(String(format: "%.0f%%", playbackAdaptationProfile.danmakuLoadFactor * 100))")
    }
}
