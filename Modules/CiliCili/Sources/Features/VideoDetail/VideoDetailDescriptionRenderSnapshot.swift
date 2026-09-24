import Foundation

struct VideoDetailDescriptionRenderSnapshot: Equatable {
    var titleText = ""
    var owner: VideoOwner?
    var viewCountText = "-"
    var fanCountText = "粉丝 -"
    var publishDateText = "-"
    var publishDateSubtitleText: String?
    var descriptionText = "这个视频暂时没有简介。"
    var hasResolvedDetailMetadata = false
    var canFavorite = false
    var shareURL: URL?
    var shareSubject = ""
    var shareMessage = "来自哔哩哔哩的视频"
    var isFollowing = false
    var isMutatingInteraction = false

    init() {}

    init(viewModel: VideoDetailViewModel) {
        let detail = viewModel.detail
        let trimmedTitle = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)

        titleText = detail.title
        owner = detail.owner
        viewCountText = BiliFormatters.compactCount(detail.stat?.view)
        fanCountText = viewModel.uploaderFanCountText
        publishDateText = viewModel.detailDisplayMetrics.publishDateText
        publishDateSubtitleText = viewModel.detailDisplayMetrics.publishDateSubtitleText
        let description = (detail.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionText = description.isEmpty ? "这个视频暂时没有简介。" : description
        hasResolvedDetailMetadata = viewModel.hasResolvedDetailMetadata
        canFavorite = viewModel.detailDisplayMetrics.canFavorite
        shareURL = Self.videoShareURL(for: detail)
        shareSubject = trimmedTitle
        shareMessage = trimmedTitle.isEmpty ? "来自哔哩哔哩的视频" : trimmedTitle
        isFollowing = viewModel.interactionState.isFollowing
        isMutatingInteraction = viewModel.isMutatingFollow
    }

    private static func videoShareURL(for video: VideoItem) -> URL? {
        let bvid = video.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bvid.isEmpty else { return nil }
        return URL(string: "https://www.bilibili.com/video/\(bvid)")
    }
}
