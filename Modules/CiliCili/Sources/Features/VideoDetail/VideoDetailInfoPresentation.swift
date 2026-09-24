import Foundation

struct VideoDetailInfoPresentation {
    let titleText: String
    let descriptionText: String
    let hasDescriptionContent: Bool
    let metadataText: String

    init(store: VideoDetailDescriptionRenderStore, isExpanded: Bool) {
        titleText = Self.titleText(from: store)
        descriptionText = store.descriptionText

        let descriptionPreview = Self.collapsedDescriptionPreview(descriptionText)
        hasDescriptionContent = descriptionPreview != nil
        metadataText = Self.metadataText(
            store: store,
            descriptionPreview: isExpanded ? nil : descriptionPreview
        )
    }

    private static func titleText(from store: VideoDetailDescriptionRenderStore) -> String {
        if !store.titleText.isEmpty {
            return store.titleText
        }
        return "视频详情"
    }

    private static func metadataText(
        store: VideoDetailDescriptionRenderStore,
        descriptionPreview: String?
    ) -> String {
        var parts = [String]()
        let ownerName = store.owner?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !ownerName.isEmpty {
            parts.append(ownerName)
        }

        if store.viewCountText != "-" {
            parts.append("\(store.viewCountText)观看")
        }

        if store.publishDateText != "-" {
            parts.append(store.publishDateText)
        }

        if let descriptionPreview {
            parts.append(descriptionPreview)
        }

        return parts.isEmpty ? "视频详情" : parts.joined(separator: "  ")
    }

    private static func collapsedDescriptionPreview(_ text: String) -> String? {
        let trimmed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "这个视频暂时没有简介。" else { return nil }
        return trimmed
    }
}
