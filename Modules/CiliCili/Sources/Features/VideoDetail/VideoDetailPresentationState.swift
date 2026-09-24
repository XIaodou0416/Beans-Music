import Foundation

struct VideoDetailPresentationState {
    var displayMetrics = VideoDetailDisplayMetrics()
    var uploaderProfile: UploaderProfile?
    var uploaderFanCountText = "粉丝 -"
    var didRecordDetailLoadedEvent = false
    var hasResolvedDetailMetadata = false
}

extension VideoDetailViewModel {
    var detailDisplayMetrics: VideoDetailDisplayMetrics {
        get { detailPresentationState.displayMetrics }
        set { detailPresentationState.displayMetrics = newValue }
    }

    var uploaderProfile: UploaderProfile? {
        get { detailPresentationState.uploaderProfile }
        set {
            detailPresentationState.uploaderProfile = newValue
            refreshUploaderFanCountText()
        }
    }

    var uploaderFanCountText: String {
        get { detailPresentationState.uploaderFanCountText }
        set {
            detailPresentationState.uploaderFanCountText = newValue
            scheduleRenderStoreSync(.description)
        }
    }

    var didRecordDetailLoadedEvent: Bool {
        get { detailPresentationState.didRecordDetailLoadedEvent }
        set { detailPresentationState.didRecordDetailLoadedEvent = newValue }
    }

    var hasResolvedDetailMetadata: Bool {
        get { detailPresentationState.hasResolvedDetailMetadata }
        set {
            detailPresentationState.hasResolvedDetailMetadata = newValue
            scheduleRenderStoreSync(.description)
        }
    }
}
