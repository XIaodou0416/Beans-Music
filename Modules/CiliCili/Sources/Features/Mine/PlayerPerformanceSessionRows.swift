import SwiftUI

struct PlayerPerformanceSessionRow: View {
    let session: PlayerPerformanceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlayerPerformanceSessionHeader(session: session)
            PlayerPerformanceSessionMetricsGrid(session: session)
            PlayerPerformanceSessionSummary(session: session)
            PlayerPerformanceSessionDetailMessages(session: session)
            PlayerPerformanceSessionTimeline(session: session)
            PlayerPerformanceSessionFailureLabel(session: session)
        }
        .padding(.vertical, 6)
    }
}

struct PlayerPerformanceExceptionRow: View {
    let session: PlayerPerformanceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(session.title ?? session.metricsID, systemImage: exceptionIcon)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(session.lastUpdatedAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(exceptionSummary)
                .font(.caption)
                .foregroundStyle(exceptionColor)
                .lineLimit(2)

            if let last = session.timeline.last {
                Text(last.compactDescription)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var exceptionIcon: String {
        if session.failureMessage != nil { return "exclamationmark.triangle" }
        if session.bufferCount >= 2 { return "hourglass" }
        if session.resumeRecoverySlowCount > 0 { return "clock.arrow.circlepath" }
        if session.seekRecoverySlowCount > 0 { return "speedometer" }
        if (session.accessLogStallCount ?? 0) > 0 { return "dot.radiowaves.left.and.right" }
        return "forward.frame"
    }

    private var exceptionSummary: String {
        if let failureMessage = session.failureMessage {
            return failureMessage
        }
        if session.bufferCount >= 2 {
            return "缓冲 \(session.bufferCount) 次，建议检查 CDN 或降低启动画质。"
        }
        if session.resumeRecoverySlowCount > 0 {
            return "续播落点偏慢 \(session.resumeRecoverySlowCount) 次，已进入更保守的开播保护策略。"
        }
        if session.seekRecoverySlowCount > 0 {
            return "Seek 恢复偏慢 \(session.seekRecoverySlowCount) 次，已进入更保守的播放保护策略。"
        }
        if let accessLogStallCount = session.accessLogStallCount, accessLogStallCount > 0 {
            return "系统 AccessLog 记录 stall \(accessLogStallCount) 次，建议复测 CDN 或降低开播画质。"
        }
        return "Seek \(session.seekCount) 次，已进入更保守的播放保护策略。"
    }

    private var exceptionColor: Color {
        session.failureMessage != nil ? .red : .orange
    }
}
