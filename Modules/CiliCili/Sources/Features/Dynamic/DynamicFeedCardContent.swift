import SwiftUI

struct DynamicStandardFeedCardContent: View {
    let item: DynamicFeedItem
    let display: DynamicFeedCardDisplayModel
    let contentWidth: CGFloat?
    let usesExternalHorizontalInsets: Bool
    @Binding var isTextExpanded: Bool
    let onShowComments: () -> Void
    let onOpenDetail: (() -> Void)?
    let onOpenOriginalDetail: ((DynamicOriginalItem) -> Void)?
    let showsActionBar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                authorHeader
                    .padding(.horizontal, horizontalContentInset)

                DynamicFeedCardTextSection(
                    display: display,
                    preferredWidth: textWidth,
                    onOpenDetail: onOpenDetail,
                    isTextExpanded: $isTextExpanded
                )
                .padding(.horizontal, horizontalContentInset)

                if let paidContent = display.paidContent, display.paidContentRendersAsTextOnly {
                    DynamicPaidArticleTextRouteLink(content: paidContent, chargeURL: display.paidChargeURL) {
                        DynamicPaidArticleTextPreview(content: paidContent)
                    }
                    .padding(.horizontal, horizontalContentInset)
                } else if let paidContent = display.paidContent {
                    DynamicPaidContentRouteLink(content: paidContent, video: display.paidVideo) {
                        DynamicPaidContentPreview(content: paidContent, style: .large)
                    }
                } else if let video = display.video {
                    VideoRouteLink(video) {
                        DynamicArchivePreview(video: video, style: .large, showsHeader: false)
                    }
                }

                if let live = display.live {
                    DynamicLiveRouteLink(room: display.liveRoom) {
                        DynamicLivePreview(live: live, style: .large)
                    }
                }

                if !display.imageItems.isEmpty {
                    DynamicImageThumbnailStrip(
                        images: display.imageItems,
                        availableWidth: contentWidth
                    )
                }

                if let original = item.original {
                    DynamicOriginalPreview(
                        item: original,
                        parentID: item.id,
                        contentWidth: textWidth,
                        onOpenDetail: onOpenOriginalDetail.map { action in
                            { action(original) }
                        }
                    )
                    .padding(.horizontal, horizontalContentInset)
                } else if item.isForward {
                    DynamicForwardUnavailableView()
                        .padding(.horizontal, horizontalContentInset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicDetailTapAction(
                onOpenDetail,
                identifier: "dynamic.feed.detailTapArea.\(display.dynamicID).content"
            )

            if showsActionBar {
                DynamicFeedCardActionSection(
                    item: item,
                    display: display,
                    onShowComments: onShowComments
                )
            }
        }
        .padding(.top, 5)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorHeader: some View {
        DynamicFeedAuthorHeader(display: display)
    }

    private var textWidth: CGFloat? {
        contentWidth
    }

    private var horizontalContentInset: CGFloat {
        usesExternalHorizontalInsets ? 0 : 12
    }
}

extension View {
    @ViewBuilder
    func dynamicDetailTapAction(
        _ action: (() -> Void)?,
        identifier: String,
        accessibilityLabel: String = "查看动态详情"
    ) -> some View {
        if let action {
            background {
                Button(action: action) {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier)
            }
            .accessibilityAction(named: Text(accessibilityLabel), action)
        } else {
            self
        }
    }
}
