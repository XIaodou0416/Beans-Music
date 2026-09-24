import SwiftUI

struct DynamicOriginalPreview: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let item: DynamicOriginalItem
    let parentID: String
    let contentWidth: CGFloat?
    let onOpenDetail: (() -> Void)?
    private let video: VideoItem?
    private let live: DynamicLive?
    private let liveRoom: LiveRoom?
    private let paidContent: DynamicPaidContent?
    private let paidVideo: VideoItem?
    private let paidContentRendersAsTextOnly: Bool
    private let paidChargeURL: URL?
    private let authorOwner: VideoOwner?
    private let imageItems: [DynamicImageItem]
    private let textSegments: [DynamicTextSegment]
    private let textInput: DynamicAttributedTextInput
    private let topLevelDisplayText: String?

    init(
        item: DynamicOriginalItem,
        parentID: String,
        contentWidth: CGFloat? = nil,
        onOpenDetail: (() -> Void)? = nil
    ) {
        self.item = item
        self.parentID = parentID
        self.contentWidth = contentWidth
        self.onOpenDetail = onOpenDetail
        self.video = item.archive?.asVideoItem(author: item.author)
        self.live = item.live
        self.liveRoom = item.live?.asLiveRoom(author: item.author)
        self.paidContent = item.paidContent
        self.paidVideo = item.paidContent?.asVideoItem(author: item.author)
        self.paidContentRendersAsTextOnly = item.paidContent?.isChargeArticleLike == true
        self.paidChargeURL = item.paidContent?.chargePageURL(author: item.author)
        self.authorOwner = item.author?.owner
        self.imageItems = item.imageItems.filter { $0.normalizedURL != nil }
        self.textSegments = item.textSegments
        self.textInput = .dynamicFeedBody(
            segments: item.textSegments,
            emoteSize: 20,
            maxLines: 5
        )
        self.topLevelDisplayText = DynamicTextSegment.displayText(from: item.textSegments)
    }

    var body: some View {
        originalContent
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.78))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(appTintColor.opacity(0.58))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dynamicDetailTapAction(
            onOpenDetail,
            identifier: "dynamic.feed.originalDetailTapArea.\(parentID).\(item.idStr)",
            accessibilityLabel: "查看原动态详情"
        )
    }

    @ViewBuilder
    private var originalContent: some View {
        if item.visible == false || !item.hasDisplayableContent {
            DynamicForwardUnavailableView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let author = item.author {
                    if let authorOwner, authorOwner.mid > 0 {
                        VideoOwnerRouteLink(owner: authorOwner) {
                            DynamicOriginalAuthorIdentity(author: author)
                        }
                    } else {
                        DynamicOriginalAuthorIdentity(author: author)
                    }
                }

                if topLevelDisplayText?.isEmpty == false {
                    DynamicRichTextView(
                        input: textInput,
                        preferredWidth: originalContentWidth,
                        onNonLinkTap: onOpenDetail
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dynamicCopyableText(topLevelDisplayText)
                }

                if let paidContent, paidContentRendersAsTextOnly {
                    DynamicPaidArticleTextRouteLink(content: paidContent, chargeURL: paidChargeURL) {
                        DynamicPaidArticleTextPreview(content: paidContent)
                    }
                } else if let paidContent {
                    DynamicPaidContentRouteLink(content: paidContent, video: paidVideo) {
                        DynamicPaidContentPreview(content: paidContent, style: .compact)
                    }
                } else if let video {
                    VideoRouteLink(video) {
                        DynamicArchivePreview(
                            video: video,
                            style: .compact,
                            showsCoverBadges: false
                        )
                    }
                }

                if let live {
                    DynamicLiveRouteLink(room: liveRoom) {
                        DynamicLivePreview(live: live, style: .compact)
                    }
                }

                if !imageItems.isEmpty {
                    DynamicImageThumbnailStrip(
                        images: imageItems,
                        availableWidth: originalContentWidth
                    )
                }
            }
        }
    }

    private var originalContentWidth: CGFloat? {
        contentWidth.map { max(floor($0 - 24), 0) }
    }
}
