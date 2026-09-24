import SwiftUI

struct PlaybackNetworkProbeResultRow: View {
    let result: PlaybackCDNProbeResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: result.didSucceed ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(result.didSucceed ? .green : .secondary)
                Text(result.preference.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let addressFamily = result.addressFamily {
                    Text(addressFamily.title)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Text(result.elapsedMilliseconds.map { "\($0) ms" } ?? "失败")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(result.userFacingStatus)
                if let httpStatusTitle = result.httpStatusTitle {
                    Text(httpStatusTitle)
                }
                if result.hostWasRewritten {
                    Text("已重写 Host")
                }
                if result.isWeakReference {
                    Text("弱参考")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)

            if let probedHost = result.probedHost {
                Text([probedHost, result.probePathDescription].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}
