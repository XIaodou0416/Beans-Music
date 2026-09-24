import SwiftUI

nonisolated struct VideoCardDisplayModel: Identifiable, Equatable {
    let id: String
    let title: String
    let authorName: String
    let viewText: String
    let durationText: String
    let publishTimeText: String
    let recommendReasonText: String
    let metadataSummaryText: String
    let coverURL: URL?
    let largeCoverURL: URL?
    let sourceCoverURL: URL?
    let avatarURLString: String?
    let coverAspectRatio: CGFloat

    init(video: VideoItem) {
        id = video.id
        title = video.title
        authorName = video.owner?.name ?? "Unknown"
        viewText = BiliFormatters.compactCount(video.stat?.view)
        durationText = BiliFormatters.duration(video.duration)
        let formattedPublishTime = BiliFormatters.relativeTime(video.pubdate)
        publishTimeText = formattedPublishTime.isEmpty ? "投稿" : formattedPublishTime
        recommendReasonText = video.recommendReason?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        metadataSummaryText = [
            recommendReasonText.isEmpty ? nil : recommendReasonText,
            authorName,
            viewText.isEmpty ? nil : "\(viewText)次观看",
            publishTimeText
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " · ")
        let normalizedCover = video.pic?.normalizedBiliURL()
        sourceCoverURL = normalizedCover.flatMap { URL(string: $0) }
        coverURL = normalizedCover.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 480, height: 270)) }
        largeCoverURL = normalizedCover.flatMap { URL(string: $0.biliImageThumbnailURL(maxSide: 1280)) }
        avatarURLString = video.owner?.face?.normalizedBiliURL()
        coverAspectRatio = CGFloat(video.dimension?.aspectRatio ?? 16.0 / 9.0)
    }

    func coverThumbnailURL(fitting size: CGSize, scale: CGFloat, maximumPixelLength: Int = 1280) -> URL? {
        guard let source = sourceCoverURL?.absoluteString else { return coverURL }
        return URL(string: source.biliCoverThumbnailURL(fitting: size, scale: scale, maximumPixelLength: maximumPixelLength)) ?? coverURL
    }

    func largeThumbnailURL(fitting size: CGSize, scale: CGFloat, maximumPixelLength: Int = 1280) -> URL? {
        guard let source = sourceCoverURL?.absoluteString else { return largeCoverURL ?? coverURL }
        return URL(string: source.biliImageThumbnailURL(fitting: size, scale: scale, maximumPixelLength: maximumPixelLength)) ?? largeCoverURL ?? coverURL
    }

    func coverTargetPixelSize(fitting size: CGSize, scale: CGFloat, maximumPixelLength: Int = 1280) -> Int {
        String.biliThumbnailMaxPixelSide(fitting: size, scale: scale, maximumPixelLength: maximumPixelLength)
    }

    var coverLoadIdentity: String {
        sourceCoverURL?.absoluteString ?? coverURL?.absoluteString ?? id
    }
}
