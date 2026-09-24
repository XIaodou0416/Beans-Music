import SwiftUI

struct VideoDetailPlayURLNotice: View {
    @ObservedObject var placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let retry: () -> Void

    var body: some View {
        if placeholderStore.selectedPlayVariant == nil {
            switch placeholderStore.playURLState {
            case .failed(let message):
                VideoDetailPlayURLFailedNotice(
                    message: message,
                    retry: retry
                )
            case .idle where placeholderStore.isDetailLoaded:
                VideoDetailPlayURLRetryButton(
                    title: "加载播放地址",
                    systemImage: "play.rectangle",
                    retry: retry
                )
            default:
                EmptyView()
            }
        } else if placeholderStore.selectedPlayVariant?.isPlayable == false {
            Label("当前档位暂不可播放", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
