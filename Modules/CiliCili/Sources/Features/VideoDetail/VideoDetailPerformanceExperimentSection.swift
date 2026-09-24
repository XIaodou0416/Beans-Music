import SwiftUI

struct PlayerPerformanceOverlayExperimentSection: View {
    let snapshot: VideoDetailPerformanceExperimentSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("刷新优化")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }

            row(title: "状态", value: snapshot.isBareSurfaceTransitionActive ? "旋转中，叠层冻结" : "运行中")
            row(title: "内容外壳", value: "窄观察")
            row(title: "视频画面", value: snapshot.directUIKitSurfaceEnabled ? "UIKit 直连" : "SwiftUI 桥接")
            row(title: "播放叠层", value: snapshot.narrowPlayerOverlayObservationEnabled ? "窄刷新" : "兼容刷新")
            row(title: "叠层保留", value: snapshot.narrowPlayerOverlayObservationEnabled ? "稳定叠层" : "按播放器重建")
            row(title: "播放器替换", value: snapshot.narrowPlayerOverlayObservationEnabled ? "原位重绑 \(snapshot.playerRebindCount) 次" : "兼容重建")
            row(title: "进度刷新", value: "叶子控件")
            row(title: "旋转策略", value: "视频层优先")
            row(title: "旋转次数", value: "\(snapshot.rotationTransitionCount)")
            row(title: "最近冻结", value: millisecondsText(snapshot.lastBareSurfaceDurationMilliseconds))
            row(title: "累计冻结", value: millisecondsText(snapshot.totalBareSurfaceDurationMilliseconds))
            row(title: "叠层发布", value: "\(snapshot.overlayPublishCount)")
            row(title: "播放状态", value: "\(snapshot.playerStatePublishCount)")
            row(title: "设置状态", value: "\(snapshot.settingsStatePublishCount)")
            row(title: "旋转暂存", value: "\(snapshot.overlayDeferredCount)")
            row(title: "恢复合并", value: "\(snapshot.overlayFlushCount)")
            row(title: "最近事件", value: snapshot.lastEvent)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PlayerPerformanceOverlayFormatting.sectionBackground,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.55), lineWidth: 0.7)
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2.monospacedDigit())
    }

    private func millisecondsText(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "-" }
        if milliseconds >= 1_000 {
            return String(format: "%.2fs", Double(milliseconds) / 1_000)
        }
        return "\(milliseconds)ms"
    }
}
