import Foundation

extension PlaybackNetworkDiagnosticFormat {
    static func playbackURLPreferenceSummary(_ snapshot: PlaybackURLPreferenceSnapshot) -> String {
        "\(snapshot.networkTitle) · \(playbackURLThroughputText(snapshot.averageKilobytesPerSecond)) · 失败 \(snapshot.failureRatePercent)% · \(snapshot.attemptCount) 样本 · \(snapshot.lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    static func hlsBridgeSourceSummary(_ snapshot: HLSBridgeSourceDiagnosticsSnapshot) -> String {
        var parts = [
            playbackURLThroughputText(snapshot.averageKilobytesPerSecond),
            "失败 \(snapshot.failureRatePercent)%",
            "\(snapshot.attemptCount) 样本"
        ]
        if snapshot.isSessionAvoided {
            let expires = snapshot.avoidanceExpiresAt.map {
                $0.formatted(date: .omitted, time: .shortened)
            } ?? "-"
            parts.append("避让 \(snapshot.avoidanceReason ?? "-") 至 \(expires)")
        }
        return parts.joined(separator: " · ")
    }

    static func playbackURLThroughputText(_ kilobytesPerSecond: Int) -> String {
        guard kilobytesPerSecond > 0 else { return "吞吐 -" }
        if kilobytesPerSecond >= 1024 {
            return String(format: "%.1f MB/s", Double(kilobytesPerSecond) / 1024)
        }
        return "\(kilobytesPerSecond) KB/s"
    }
}
