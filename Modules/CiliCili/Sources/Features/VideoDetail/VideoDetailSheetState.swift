import Foundation
import SwiftUI

@MainActor
final class VideoDetailMoreControlsSheetPresentation: Identifiable {
    let id = UUID()
    let playerViewModel: PlayerStateViewModel
    private let onDismiss: () -> Void
    private var hasFinished = false

    init(
        playerViewModel: PlayerStateViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.playerViewModel = playerViewModel
        self.onDismiss = onDismiss
    }

    func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onDismiss()
    }
}

struct VideoDetailCommentThreadSheetPresentation: Identifiable {
    let id = UUID()
    let rootComment: Comment
    let secondaryID: Int?
}

@MainActor
enum VideoDetailSheetRoute: Identifiable {
    case commentThread(VideoDetailCommentThreadSheetPresentation)
    case moreControls(VideoDetailMoreControlsSheetPresentation)

    var id: UUID {
        switch self {
        case .commentThread(let presentation):
            presentation.id
        case .moreControls(let presentation):
            presentation.id
        }
    }
}

struct VideoDetailSheetState {
    var route: Binding<VideoDetailSheetRoute?>
    var isShowingFavoriteFolders: Binding<Bool>
    var isShowingCoinPicker: Binding<Bool>
    var isShowingDanmakuSettings: Binding<Bool>
    var isShowingNetworkDiagnostics: Binding<Bool>
}
