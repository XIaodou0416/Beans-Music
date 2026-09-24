import SwiftUI

struct PlayerAutoOptimizationSummaryRow: View {
    let profile: PlayerPlaybackAdaptationProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(profileTitle, systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(profileColor)

            Text(profileMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var profileTitle: String {
        guard profile.isEnabled else {
            return "当前策略：已关闭"
        }
        switch profile.level {
        case .normal:
            return "当前策略：正常"
        case .fallback:
            return "当前策略：快速回退"
        case .cautious:
            return "当前策略：谨慎加载"
        case .slow:
            return "当前策略：慢网保护"
        }
    }

    private var profileMessage: String {
        guard profile.isEnabled else {
            return "不会根据历史表现自动调整画质、预加载或 CDN 复测。"
        }
        switch profile.level {
        case .normal:
            return "保持默认画质和正常预加载。"
        case .fallback:
            return "优先使用缓存回退，减少首屏等待。"
        case .cautious:
            return "降低开播画质上限并减少后台预加载。"
        case .slow:
            return "强制轻量开播，暂停非必要预热，并触发 CDN 复测。"
        }
    }

    private var profileColor: Color {
        guard profile.isEnabled else {
            return .secondary
        }
        switch profile.level {
        case .normal:
            return .green
        case .fallback:
            return .blue
        case .cautious:
            return .orange
        case .slow:
            return .red
        }
    }
}
