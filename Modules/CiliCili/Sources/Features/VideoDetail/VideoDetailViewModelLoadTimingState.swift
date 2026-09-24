import Foundation

struct VideoDetailViewModelLoadTimingState {
    var detailLoadStartTime: CFTimeInterval?
    var playURLLoadStartTime: CFTimeInterval?
    var relatedLoadStartTime: CFTimeInterval?
}

extension VideoDetailViewModel {
    var detailLoadStartTime: CFTimeInterval? {
        get { loadTiming.detailLoadStartTime }
        set { loadTiming.detailLoadStartTime = newValue }
    }

    var playURLLoadStartTime: CFTimeInterval? {
        get { loadTiming.playURLLoadStartTime }
        set { loadTiming.playURLLoadStartTime = newValue }
    }

    var relatedLoadStartTime: CFTimeInterval? {
        get { loadTiming.relatedLoadStartTime }
        set { loadTiming.relatedLoadStartTime = newValue }
    }
}
