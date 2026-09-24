import SwiftUI

struct LiveDanmakuDiagnosticsHUD: View {
    let snapshot: LiveDanmakuDiagnosticSnapshot
    let isExpanded: Bool

    private var rows: [(title: String, value: String)] {
        var values: [(title: String, value: String)] = [
            ("配置", snapshot.configSummary),
            ("回填", snapshot.historySummary),
            ("连接", snapshot.connectionSummary),
            ("收包", snapshot.receiveSummary),
            ("弹幕", snapshot.commandSummary)
        ]
        if isExpanded {
            values.append(("覆盖层", snapshot.renderSummary))
            values.append(("节点", snapshot.endpointSummary))
            values.append(("心跳", "\(snapshot.heartbeatReplyCount)/\(snapshot.heartbeatSentCount)"))
            values.append(("解析", "\(snapshot.inflateSuccessCount) 成功 · \(snapshot.inflateFailureCount) 失败"))
            values.append(("重连", "\(snapshot.reconnectCount) 次"))
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveDanmakuDiagnosticsHeader(snapshot: snapshot)

            Text(snapshot.conclusion)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(isExpanded ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)

            LiveDanmakuDiagnosticsRows(rows: rows)

            if isExpanded, let lastCommandName = snapshot.lastCommandName {
                Text("最后命令 \(lastCommandName)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if isExpanded, let lastEndpointError = snapshot.lastEndpointError {
                Text("节点失败 \(lastEndpointError)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(width: isExpanded ? 360 : 292, alignment: .leading)
        .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }
}

private struct LiveDanmakuDiagnosticsHeader: View {
    let snapshot: LiveDanmakuDiagnosticSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.phase.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(snapshot.phase.tintColor)
                .frame(width: 18, height: 18)

            Text("弹幕诊断")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Text(snapshot.phase.title)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(snapshot.phase.tintColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(snapshot.phase.tintColor.opacity(0.18), in: Capsule())
        }
    }
}

private struct LiveDanmakuDiagnosticsRows: View {
    let rows: [(title: String, value: String)]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows, id: \.title) { row in
                LiveDanmakuDiagnosticsRow(title: row.title, value: row.value)
            }
        }
    }
}

private struct LiveDanmakuDiagnosticsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 44, alignment: .leading)

            Text(value)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
        }
    }
}

private extension LiveDanmakuDiagnosticPhase {
    var tintColor: Color {
        switch self {
        case .rendering:
            return .green
        case .receiving, .waitingForPackets:
            return .cyan
        case .fetchingConfig, .connecting, .authenticating, .reconnecting:
            return .yellow
        case .failed:
            return .red
        case .idle, .stopped:
            return .white.opacity(0.72)
        }
    }
}
