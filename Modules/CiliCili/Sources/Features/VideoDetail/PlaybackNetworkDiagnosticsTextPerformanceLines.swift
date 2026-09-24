import Foundation

@MainActor
extension PlaybackNetworkDiagnosticsTextBuilder {
    func appendPerformanceSessionLines(to lines: inout [String]) {
        guard let session = performanceSession else { return }
        lines.append("总首帧：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(session.firstFrameTotalMilliseconds))")
        lines.append("播放器首帧：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(session.firstFramePlayerMilliseconds))")
        lines.append("启动取流来源：\(PlaybackNetworkDiagnosticFormat.startupPlayURLTitle(for: session))")
        lines.append("启动档位：\(PlaybackNetworkDiagnosticFormat.startupQualityTitle(session.startupQuality))")
        lines.append("目标档位：\(PlaybackNetworkDiagnosticFormat.startupQualityTitle(session.startupTargetQuality))")
        lines.append("PiliPlus 风格 AV1 取流：已启用")
        lines.append("HLS Route：\(PlaybackNetworkDiagnosticFormat.startupRoutePlanTitle(for: session))")
        if session.startupRoutePrebuildState != nil {
            lines.append("Route 预构建：\(PlaybackNetworkDiagnosticFormat.startupRoutePrebuildTitle(for: session))")
        }
        lines.append("启动包：\(PlaybackNetworkDiagnosticFormat.startupPackageTitle(for: session))")
        lines.append("首片预热：\(PlaybackNetworkDiagnosticFormat.startupRangeWarmTitle(for: session))")
        appendOptional("首帧调度", session.startupSchedulerMessage, to: &lines)
        appendOptional("播放反馈", session.networkMessage, to: &lines)
        appendOptional("首帧分段", session.startupBreakdownMessage, to: &lines)
        appendOptional("启动阶段空档", session.startupGapMessage, to: &lines)
        appendOptional("HLS 启动请求", session.hlsStartupMessage, to: &lines)
        appendOptional("启动决策", session.startupDecisionMessage, to: &lines)
        if let resumeApplyMilliseconds = session.resumeApplyMilliseconds {
            lines.append("续播 Seek：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(resumeApplyMilliseconds))")
        }
        if session.resumeRecoveryCount > 0 {
            lines.append("续播验证：\(session.resumeRecoveryCount) 次，慢 \(session.resumeRecoverySlowCount) 次")
        }
        if let lastResumeRecoveryMilliseconds = session.lastResumeRecoveryMilliseconds {
            lines.append("续播落点：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(lastResumeRecoveryMilliseconds))")
        }
        lines.append("Seek 次数：\(session.seekCount)")
        if session.seekRecoveryCount > 0 {
            lines.append("Seek 恢复：\(session.seekRecoveryCount) 次")
        }
        if session.playbackRecoveryCount > 0 {
            lines.append("播放恢复：\(session.playbackRecoveryCount) 次，失败 \(session.playbackRecoveryFailureCount) 次")
        }
        appendOptional("AccessLog", session.accessLogMessage, to: &lines)
        if session.speedBoostCount > 0 {
            lines.append("长按倍速：\(session.speedBoostCount) 次，中断 \(session.speedBoostInterruptionCount) 次")
        }
        if !session.timeline.isEmpty {
            lines.append("播放时间线：")
            lines.append(contentsOf: session.timeline.suffix(8).map { "  \($0.compactDescription)" })
        }
        appendOptional("最近 Seek", session.seekMessage, to: &lines)
        appendOptional("最近续播验证", session.resumeRecoveryMessage, to: &lines)
        appendOptional("最近恢复", session.seekRecoveryMessage, to: &lines)
        appendOptional("最近播放恢复", session.playbackRecoveryMessage, to: &lines)
        appendOptional("最近倍速", session.speedBoostMessage, to: &lines)
    }
}
