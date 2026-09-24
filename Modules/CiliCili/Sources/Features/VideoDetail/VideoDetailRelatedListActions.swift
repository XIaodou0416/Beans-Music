import Foundation

struct VideoDetailRelatedListActions {
    let beginPreload: (VideoItem) async -> Void

    func handleRowAppear(_ item: VideoDetailRelatedDisplayItem) async {
        await beginPreload(item.video)
    }
}
