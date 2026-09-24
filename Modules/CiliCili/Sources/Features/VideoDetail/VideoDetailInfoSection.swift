import SwiftUI

struct VideoDetailInfoBlock: View {
    @ObservedObject var store: VideoDetailDescriptionRenderStore
    @State private var isExpanded = false

    var body: some View {
        Group {
            if store.hasResolvedDetailMetadata {
                VideoDetailResolvedInfoContent(
                    store: store,
                    isExpanded: $isExpanded
                )
            } else {
                VideoDetailInfoLoadingPlaceholder(titleText: store.titleText)
            }
        }
    }
}
