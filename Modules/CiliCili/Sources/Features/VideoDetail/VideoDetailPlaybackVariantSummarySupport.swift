import Foundation

extension VideoDetailViewModel {
    nonisolated static func qualitySummary(_ variants: [PlayVariant]) -> String {
        let summary = variants
            .filter(\.isPlayable)
            .map { variant in
                let kind = variant.isProgressiveFastStart ? "p" : "d"
                return "\(variant.quality)\(kind)"
            }
            .joined(separator: ",")
        return summary.isEmpty ? "-" : summary
    }
}
