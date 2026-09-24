import SwiftUI

@MainActor
struct VideoDetailViewCloseActions {
    let holder: VideoDetailViewModelHolder
    let dismiss: DismissAction
    let onRequestClose: (() -> Void)?
    let onPopOne: (() -> Void)?

    func dismissVideoDetail(
        presentationState: Binding<VideoDetailViewPresentationState>
    ) {
        guard !presentationState.wrappedValue.isClosingDetail else { return }
        presentationState.wrappedValue.isClosingDetail = true
        holder.viewModel?.stopPlaybackForNavigation()
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    /// 返回按钮：只 pop 一层（回到上一个详情页或来源页）。复用与
    /// dismissVideoDetail 相同的播放清理，但走 onPopOne（removeLast）而非清空整栈。
    func popOneVideoLevel(
        presentationState: Binding<VideoDetailViewPresentationState>
    ) {
        guard !presentationState.wrappedValue.isClosingDetail else { return }
        presentationState.wrappedValue.isClosingDetail = true
        holder.viewModel?.stopPlaybackForNavigation()
        if let onPopOne {
            onPopOne()
        } else if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }
}
