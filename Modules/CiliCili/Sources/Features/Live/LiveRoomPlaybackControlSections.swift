import SwiftUI

extension LiveRoomContentView {
    @ViewBuilder
    func liveStreamMenu(_ viewModel: LiveRoomViewModel) -> some View {
        LiveStreamMenu(viewModel: viewModel)
    }

    @ViewBuilder
    func liveQualityMenu(_ viewModel: LiveRoomViewModel) -> some View {
        LiveQualityMenu(viewModel: viewModel)
    }

    func livePlayerAccessory(
        _ viewModel: LiveRoomViewModel,
        usesCompactLayout: Bool
    ) -> some View {
        LivePlayerAccessory(
            viewModel: viewModel,
            usesCompactLayout: usesCompactLayout
        )
    }

    @ViewBuilder
    func liveLoadingPlaceholder(_ viewModel: LiveRoomViewModel) -> some View {
        ZStack {
            Color.black

            if case .failed(let message) = viewModel.state {
                LivePlayerFailurePlaceholder(message: message, retry: viewModel.reload)
            } else {
                LivePlayerLoadingPlaceholder(
                    title: viewModel.title.nilIfEmpty ?? "正在进入直播间",
                    subtitle: viewModel.currentQualityTitle ?? viewModel.currentStreamTitle ?? "正在拉取直播流"
                )
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }
}
