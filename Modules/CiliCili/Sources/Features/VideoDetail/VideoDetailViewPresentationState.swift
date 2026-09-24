import Foundation

struct VideoDetailViewPresentationState {
    var selectedContentTab: VideoDetailContentTab = .detail
    var sheetRoute: VideoDetailSheetRoute?
    var isShowingDanmakuSettings = false
    var isShowingFavoriteFolders = false
    var isShowingCoinPicker = false
    var isShowingNetworkDiagnostics = false
    var isClosingDetail = false
}
