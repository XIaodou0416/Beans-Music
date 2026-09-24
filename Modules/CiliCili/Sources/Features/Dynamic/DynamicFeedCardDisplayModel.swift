import SwiftUI

struct DynamicFeedCardDisplayModel {
    let dynamicID: String
    let video: VideoItem?
    let videoDisplay: VideoCardDisplayModel?
    let live: DynamicLive?
    let liveRoom: LiveRoom?
    let paidContent: DynamicPaidContent?
    let paidVideo: VideoItem?
    let paidContentRendersAsTextOnly: Bool
    let paidChargeURL: URL?
    let authorOwner: VideoOwner?
    let authorAvatarURLString: String?
    let authorName: String
    let imageItems: [DynamicImageItem]
    let textSegments: [DynamicTextSegment]
    let collapsedTextInput: DynamicAttributedTextInput
    let expandedTextInput: DynamicAttributedTextInput
    let topLevelDisplayText: String?
    let publishTimeText: String
    let usesHomeVideoCardStyle: Bool
    let usesSeparatedDynamicLayout: Bool
    let supportsDetailNavigation: Bool
    let initialLikeCount: Int
    let commentTitle: String
    let repostTitle: String
    let shareURL: URL?
    let shareTitle: String
    let shareMessage: String

    init(item: DynamicFeedItem) {
        let video = item.archive?.asVideoItem(author: item.author)
        let live = item.live
        let paidContent = item.paidContent
        let paidVideo = paidContent?.asVideoItem(author: item.author)
        let paidContentRendersAsTextOnly = paidContent?.isChargeArticleLike == true
        let imageItems = item.imageItems.filter { $0.normalizedURL != nil }
        let textSegments = item.textSegments
        let topLevelDisplayText = DynamicTextSegment.displayText(from: textSegments)
        let authorName = item.author?.name ?? "Unknown"
        let isPureTextDynamic = video == nil
            && live == nil
            && paidContent == nil
            && imageItems.isEmpty
            && item.original == nil
            && !item.isForward
            && !(topLevelDisplayText?.isEmpty ?? true)

        self.dynamicID = item.idStr
        self.video = video
        self.videoDisplay = video.map(VideoCardDisplayModel.init(video:))
        self.live = live
        self.liveRoom = live?.asLiveRoom(author: item.author)
        self.paidContent = paidContent
        self.paidVideo = paidVideo
        self.paidContentRendersAsTextOnly = paidContentRendersAsTextOnly
        self.paidChargeURL = paidContent?.chargePageURL(author: item.author)
        self.authorOwner = item.author?.owner
        self.authorAvatarURLString = item.author?.face?.normalizedBiliURL()
        self.authorName = authorName
        self.imageItems = imageItems
        self.textSegments = textSegments
        self.collapsedTextInput = .dynamicFeedBody(segments: textSegments, emoteSize: 23, maxLines: 6)
        self.expandedTextInput = .dynamicFeedBody(segments: textSegments, emoteSize: 23, maxLines: nil)
        self.topLevelDisplayText = topLevelDisplayText
        self.publishTimeText = Self.publishTime(for: item.author)
        self.usesHomeVideoCardStyle = video != nil
            && paidContent == nil
            && item.original == nil
            && !item.isForward
        self.usesSeparatedDynamicLayout = item.original != nil
            || item.isForward
            || (!imageItems.isEmpty && video == nil)
            || isPureTextDynamic
        self.supportsDetailNavigation = Self.supportsDetailNavigation(
            hasTopLevelText: !(topLevelDisplayText?.isEmpty ?? true),
            imageCount: imageItems.count,
            isForward: item.isForward || item.original != nil,
            hasVideo: video != nil,
            hasLive: live != nil,
            hasPaidContent: paidContent != nil
        )
        self.initialLikeCount = item.likeCount ?? 0
        self.commentTitle = Self.statTitle(count: item.replyCount, fallback: "评论")
        self.repostTitle = Self.statTitle(count: item.repostCount, fallback: "转发")
        self.shareURL = Self.shareURL(item: item, video: video, live: live, paidContent: paidContent)
        self.shareTitle = Self.shareTitle(authorName: authorName, text: topLevelDisplayText, video: video, live: live, paidContent: paidContent)
        self.shareMessage = "\(authorName)：\(self.shareTitle)"
    }

    static func statTitle(count: Int?, fallback: String) -> String {
        guard let count, count > 0 else { return fallback }
        return BiliFormatters.compactCount(count)
    }

    static func supportsDetailNavigation(
        hasTopLevelText: Bool,
        imageCount: Int,
        isForward: Bool,
        hasVideo: Bool,
        hasLive: Bool,
        hasPaidContent: Bool
    ) -> Bool {
        if isForward {
            return true
        }

        return !hasVideo
            && !hasLive
            && !hasPaidContent
            && (hasTopLevelText || imageCount > 0)
    }

    static func supportsDetailNavigation(original: DynamicOriginalItem) -> Bool {
        supportsDetailNavigation(
            hasTopLevelText: DynamicTextSegment.displayText(from: original.textSegments)?.isEmpty == false,
            imageCount: original.imageItems.count,
            isForward: original.type == "DYNAMIC_TYPE_FORWARD",
            hasVideo: original.archive != nil,
            hasLive: original.live != nil,
            hasPaidContent: original.paidContent != nil
        )
    }

    private static func publishTime(for author: DynamicAuthor?) -> String {
        if let timestamp = author?.pubTS, timestamp > 0 {
            return BiliFormatters.relativeTime(timestamp)
        }
        return author?.pubTime ?? ""
    }

    private static func shareURL(item: DynamicFeedItem, video: VideoItem?, live: DynamicLive?, paidContent: DynamicPaidContent?) -> URL? {
        if let dynamicID = validShareID(item.idStr) {
            return URL(string: "https://t.bilibili.com/\(dynamicID)")
        }
        if let bvid = video?.bvid.trimmingCharacters(in: .whitespacesAndNewlines), !bvid.isEmpty {
            return URL(string: "https://www.bilibili.com/video/\(bvid)")
        }
        if let liveURL = live?.normalizedLinkURL {
            return liveURL
        }
        if let roomID = live?.roomID, roomID > 0 {
            return URL(string: "https://live.bilibili.com/\(roomID)")
        }
        if let paidURL = paidContent?.normalizedJumpURL {
            return paidURL
        }
        return nil
    }

    private static func shareTitle(authorName: String, text: String?, video: VideoItem?, live: DynamicLive?, paidContent: DynamicPaidContent?) -> String {
        let candidates = [
            text,
            video?.title,
            live?.displayTitle,
            paidContent?.title
        ]
        return candidates.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.first ?? "\(authorName) 的动态"
    }

    private static func validShareID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else {
            return nil
        }
        return trimmed
    }
}
