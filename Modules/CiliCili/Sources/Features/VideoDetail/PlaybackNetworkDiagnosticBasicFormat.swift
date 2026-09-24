import Foundation

extension PlaybackNetworkDiagnosticFormat {
    static func formattedMilliseconds(_ value: Int?) -> String {
        guard let value else { return "未记录" }
        if value >= 1000 {
            return String(format: "%.2f s", Double(value) / 1000)
        }
        return "\(value) ms"
    }

    static func formattedBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func hlsVariantText(_ diagnostics: PlayerEngineDiagnostics) -> String {
        let count = diagnostics.hlsVideoVariantCount
        let qualities = diagnostics.hlsVideoVariantQualities
            .map { "q\($0)" }
            .joined(separator: "/")
        guard !qualities.isEmpty else { return "\(count) 档" }
        return "\(count) 档 · \(qualities)"
    }

    static func streamModeTitle(for variant: PlayVariant?) -> String {
        guard let variant else { return "未获取" }
        if variant.videoStream != nil || variant.audioStream != nil {
            return variant.audioURL == nil ? "DASH 视频流" : "DASH 音视频分离"
        }
        return "Progressive 单流"
    }

    static func frameRateTitle(for variant: PlayVariant?) -> String {
        guard let frameRate = nilIfEmpty(variant?.frameRate) else { return "未知" }
        return frameRate.localizedCaseInsensitiveContains("fps") ? frameRate : "\(frameRate) fps"
    }

    static func bandwidthTitle(for variant: PlayVariant?) -> String {
        guard let bandwidth = variant?.bandwidth, bandwidth > 0 else { return "未知" }
        let mbps = Double(bandwidth) / 1_000_000
        return "\(String(format: "%.2f", mbps)) Mbps"
    }

    static func formattedResumeTime(_ time: TimeInterval?) -> String {
        guard let time, time.isFinite, time > 0 else { return "无" }
        return "\(BiliFormatters.duration(Int(time.rounded()))) · \(String(format: "%.1fs", time))"
    }

    static func nilIfEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
