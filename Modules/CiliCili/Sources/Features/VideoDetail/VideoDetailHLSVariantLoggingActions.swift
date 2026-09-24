import Foundation

extension VideoDetailViewModel {
    func recordHLSVideoVariantPlan(
        startupVariant: PlayVariant,
        alternateVideoRenditions: [PlayerVideoRenditionSource]
    ) {
        guard !alternateVideoRenditions.isEmpty else { return }
        let qualities = [startupVariant.quality] + alternateVideoRenditions.map(\.quality)
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: detail.bvid,
            title: detail.title,
            message: "plannedDetailVideo=\(Self.hlsQualitySummary(qualities))"
        )
    }

    nonisolated static func hlsQualitySummary(_ qualities: [Int]) -> String {
        var seen = Set<Int>()
        let uniqueQualities = qualities.filter { seen.insert($0).inserted }
        guard !uniqueQualities.isEmpty else { return "-" }
        return uniqueQualities
            .map { "q\($0)" }
            .joined(separator: "/")
    }
}
