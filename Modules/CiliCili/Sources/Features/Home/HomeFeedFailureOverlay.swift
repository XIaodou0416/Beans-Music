import SwiftUI

struct HomeFeedFailureOverlay: View {
    let state: LoadingState
    let isEmpty: Bool
    let retry: () -> Void

    var body: some View {
        if case .failed(let message) = state, isEmpty {
            ErrorStateView(title: "加载失败", message: message, retry: retry)
        }
    }
}
