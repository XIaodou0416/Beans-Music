import SwiftUI

struct DynamicSeparatedFeedCardContent: View {
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
        VStack(alignment: .leading, spacing: 9) {
            authorHeader
                .padding(.horizontal, horizontalContentInset)
                .dynamicDetailTapAction(
                    onOpenDetail,
                    identifier: "dynamic.feed.detailTapArea.\(display.dynamicID).author"
                )

            separatedStoryCard

            if showsActionBar {
                DynamicFeedCardActionSection(
                    item: item,
                    display: display,
                    onShowComments: onShowComments
                )
                .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var separatedStoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                DynamicFeedCardTextSection(
                    display: display,
                    preferredWidth: textWidth,
                    onOpenDetail: onOpenDetail,
                    isTextExpanded: $isTextExpanded
                )

                if let paidContent = display.paidContent, display.paidContentRendersAsTextOnly {
                    DynamicPaidArticleTextRouteLink(content: paidContent, chargeURL: display.paidChargeURL) {
                        DynamicPaidArticleTextPreview(content: paidContent)
                    }
                } else if let paidContent = display.paidContent {
                    DynamicPaidContentRouteLink(content: paidContent, video: display.paidVideo) {
                        DynamicPaidContentPreview(content: paidContent, style: .compact)
                    }
                }

                if !display.imageItems.isEmpty {
                    imageSquareGrid
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
                } else if item.isForward {
                    DynamicForwardUnavailableView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicDetailTapAction(
                onOpenDetail,
                identifier: "dynamic.feed.detailTapArea.\(display.dynamicID).content"
            )

        }
        .padding(.horizontal, horizontalContentInset)
        .padding(.top, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imageSquareGrid: some View {
        DynamicImageThumbnailStrip(
            images: display.imageItems,
            availableWidth: textWidth
        )
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
