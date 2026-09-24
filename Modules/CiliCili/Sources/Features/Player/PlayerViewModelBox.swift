import Combine

@MainActor
final class PlayerViewModelBox: ObservableObject {
    let viewModel: PlayerStateViewModel

    init(viewModel: PlayerStateViewModel) {
        self.viewModel = viewModel
    }
}
