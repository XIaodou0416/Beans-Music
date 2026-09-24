import SwiftUI

@MainActor
final class HomeFeedDetailOpenActions {
    private var didAutoOpenDetail = false

    func openDetail(
        for video: VideoItem,
        onVideoSelect: ((VideoItem) -> Void)?,
        appendDetailPath: (VideoItem) -> Void
    ) {
        if let onVideoSelect {
            onVideoSelect(video)
        } else {
            appendDetailPath(video)
        }
    }

    func openFirstDetailIfNeeded(
        autoOpenDetail: Bool,
        detailPathIsEmpty: Bool,
        startVideo: VideoItem?,
        videos: [VideoItem],
        onVideoSelect: ((VideoItem) -> Void)?,
        appendDetailPath: (VideoItem) -> Void
    ) {
        guard autoOpenDetail,
              !didAutoOpenDetail,
              detailPathIsEmpty else {
            return
        }

        let video = startVideo ?? videos.first
        guard let video else { return }
        didAutoOpenDetail = true
        openDetail(for: video, onVideoSelect: onVideoSelect, appendDetailPath: appendDetailPath)
    }
}
