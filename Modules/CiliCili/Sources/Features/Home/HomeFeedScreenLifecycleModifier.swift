import SwiftUI

struct HomeFeedScreenLifecycleModifier: ViewModifier {
    @ObservedObject var viewModel: HomeViewModel
    let lifecycleActions: HomeFeedScreenLifecycleModifierActions

    func body(content: Content) -> some View {
        content
            .task {
                await lifecycleActions.start()
            }
            .onChange(of: viewModel.videos.first?.id) { _, _ in
                lifecycleActions.handleVideosChanged()
            }
    }
}
