import SwiftUI

private struct MarkRelatedVideoNavigationActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var markRelatedVideoNavigation: (() -> Void)? {
        get { self[MarkRelatedVideoNavigationActionKey.self] }
        set { self[MarkRelatedVideoNavigationActionKey.self] = newValue }
    }
}

struct VideoDetailRelatedList: View {
    let items: [VideoDetailRelatedDisplayItem]
    let layout: VideoDetailRelatedListLayout
    let actions: VideoDetailRelatedListActions
    @Environment(\.markRelatedVideoNavigation) private var markRelatedVideoNavigation

    var body: some View {
        let lastRelatedVideoID = items.last?.id

        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                VStack(spacing: 0) {
                    VideoRouteLink(item.video, onOpen: markRelatedVideoNavigation) {
                        VideoDetailRelatedRow(
                            item: item,
                            coverSize: layout.coverSize
                        )
                        .equatable()
                    }
                    .buttonStyle(.plain)
                    .task(id: item.id) {
                        await actions.handleRowAppear(item)
                    }

                    if item.id != lastRelatedVideoID {
                        Divider()
                            .padding(.leading, layout.dividerLeadingPadding)
                    }
                }
            }
        }
    }
}

private struct VideoDetailRelatedRow: View, Equatable {
    let item: VideoDetailRelatedDisplayItem
    let coverSize: CGSize

    static func == (lhs: VideoDetailRelatedRow, rhs: VideoDetailRelatedRow) -> Bool {
        lhs.item == rhs.item && lhs.coverSize == rhs.coverSize
    }

    var body: some View {
        VideoCompactListRow(
            display: item.display,
            coverSize: coverSize,
            coverMaximumPixelLength: coverMaximumPixelLength,
            coverCornerRadius: VideoDetailRelatedStyle.coverCornerRadius,
            titleMinHeight: VideoDetailRelatedStyle.rowTitleMinHeight,
            authorStyle: .plain,
            metadataStyle: .related
        )
        .padding(.vertical, VideoDetailRelatedStyle.rowVerticalPadding)
    }

    private var coverMaximumPixelLength: Int {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? VideoDetailRelatedStyle.conservativeCoverMaximumPixelLength
            : VideoDetailRelatedStyle.standardCoverMaximumPixelLength
    }
}
