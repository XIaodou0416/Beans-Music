import SwiftUI

extension MinePlaybackSettingsView {
    @ViewBuilder
    var playbackURLPreferenceSummary: some View {
        if let bestSnapshot = playbackURLPreferenceSnapshots.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    MineSettingsLabel("真实播放优先", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(bestSnapshot.host)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("根据 AVPlayer 实际码率、传输耗时和新增 stall，在接口候选地址内自动修正 CDN Host 排序。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                DisclosureGroup(isExpanded: $isShowingPlaybackURLPreferenceDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(playbackURLPreferenceSnapshots) { snapshot in
                            playbackURLPreferenceSnapshotRow(snapshot)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    MineSettingsLabel("真实播放排行", systemImage: "list.bullet.rectangle")
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }

    func playbackURLPreferenceSnapshotRow(_ snapshot: PlaybackURLPreferenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snapshot.host)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(snapshot.averageMilliseconds) ms")
                    .font(.caption.monospacedDigit())
            }

            HStack(spacing: 8) {
                Text(snapshot.networkTitle)
                Text(playbackURLThroughputText(snapshot.averageKilobytesPerSecond))
                Text("失败 \(snapshot.failureRatePercent)%")
                Text("\(snapshot.attemptCount) 样本")
            }
            .font(.caption2)
            .foregroundStyle(snapshot.failureCount > 0 ? .orange : .secondary)
            .lineLimit(1)

            Text("最近 \(snapshot.lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    func playbackURLThroughputText(_ kilobytesPerSecond: Int) -> String {
        guard kilobytesPerSecond > 0 else { return "吞吐 -" }
        if kilobytesPerSecond >= 1024 {
            return String(format: "%.1f MB/s", Double(kilobytesPerSecond) / 1024)
        }
        return "\(kilobytesPerSecond) KB/s"
    }
}
