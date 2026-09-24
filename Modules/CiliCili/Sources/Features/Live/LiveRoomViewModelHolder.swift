import Combine
import SwiftUI

@MainActor
final class LiveRoomViewModelHolder: ObservableObject {
    @Published var viewModel: LiveRoomViewModel?

    private var cancellable: AnyCancellable?
    private var cleanupPlayback: (@Sendable () -> Void)?
    private var lastSnapshot: LiveRoomToolbarSnapshot?

    func configure(room: LiveRoom, api: BiliAPIClient, libraryStore: LibraryStore) {
        guard viewModel == nil else { return }
        let viewModel = LiveRoomViewModel(seedRoom: room, api: api, libraryStore: libraryStore)
        self.viewModel = viewModel
        cleanupPlayback = { [viewModel] in
            Task { @MainActor [viewModel] in
                viewModel.stopPlaybackForNavigation()
            }
        }
        lastSnapshot = LiveRoomToolbarSnapshot(viewModel)
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self, weak viewModel] in
                guard let self, let viewModel else { return }
                let snapshot = LiveRoomToolbarSnapshot(viewModel)
                guard snapshot != self.lastSnapshot else { return }
                self.lastSnapshot = snapshot
                self.objectWillChange.send()
            }
        }
    }

    deinit {
        cleanupPlayback?()
    }
}

private struct LiveRoomToolbarSnapshot: Equatable {
    let roomID: Int
    let title: String
    let anchorOwner: VideoOwner
    let liveTimeText: String?
    let isLive: Bool
    let isFollowingAnchor: Bool
    let isMutatingAnchorFollow: Bool
    let anchorUIDForFollow: Int?

    init(_ viewModel: LiveRoomViewModel) {
        roomID = viewModel.roomID
        title = viewModel.title
        anchorOwner = viewModel.anchorOwner
        liveTimeText = viewModel.liveTimeText
        isLive = viewModel.isLive
        isFollowingAnchor = viewModel.isFollowingAnchor
        isMutatingAnchorFollow = viewModel.isMutatingAnchorFollow
        anchorUIDForFollow = viewModel.anchorUIDForFollow
    }
}
