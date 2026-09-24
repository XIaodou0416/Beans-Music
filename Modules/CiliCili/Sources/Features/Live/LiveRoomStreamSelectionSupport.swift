import Foundation

struct LiveStreamMenuItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let isSelected: Bool
}

struct LiveStreamQualityMenuItem: Identifiable, Hashable {
    var id: Int { qn }
    let qn: Int
    let title: String
    let isSelected: Bool
}

extension LiveRoomViewModel {
    static func streamTitle(for candidate: LiveStreamURLCandidate, index: Int) -> String {
        var parts = ["线路 \(index + 1)"]
        if let currentQN = candidate.currentQN, currentQN > 0 {
            parts.append(liveQualityTitle(currentQN))
        }
        if let protocolName = candidate.protocolName?.uppercased(), !protocolName.isEmpty {
            parts.append(protocolName)
        } else if candidate.isLikelyHLS {
            parts.append("HLS")
        }
        if let formatName = candidate.formatName?.uppercased(), !formatName.isEmpty {
            parts.append(formatName)
        }
        if let codecName = candidate.codecName?.uppercased(), !codecName.isEmpty {
            parts.append(codecName)
        }
        return parts.joined(separator: " · ")
    }

    static func liveQualityTitle(_ quality: Int) -> String {
        switch quality {
        case 10000:
            return "原画"
        case 400:
            return "蓝光"
        case 250:
            return "超清"
        case 150:
            return "高清"
        case 80:
            return "流畅"
        default:
            return "清晰度 \(quality)"
        }
    }

    static func preferredCandidateIndex(
        in candidates: [LiveStreamURLCandidate],
        preferredQuality: Int?,
        preferredSource: LiveStreamURLCandidate?
    ) -> Int {
        guard !candidates.isEmpty else { return 0 }
        let qualityMatches = candidates.indices.filter { index in
            preferredQuality == nil || candidates[index].currentQN == preferredQuality
        }
        let searchIndices = qualityMatches.isEmpty ? Array(candidates.indices) : qualityMatches
        if let preferredSource,
           let matchingSource = searchIndices.first(where: { index in
               candidates[index].source == preferredSource.source
                   && candidates[index].protocolName == preferredSource.protocolName
                   && candidates[index].formatName == preferredSource.formatName
                   && candidates[index].codecName == preferredSource.codecName
           }) {
            return matchingSource
        }
        if let hlsIndex = searchIndices.first(where: { candidates[$0].isLikelyHLS }) {
            return hlsIndex
        }
        return searchIndices.first ?? 0
    }
}
