import SwiftUI

private struct CommentOwnerProfileRoute: Identifiable, Hashable {
    let owner: VideoOwner

    var id: Int { owner.mid }
}

struct CommentOwnerProfileNavigationContainer<Content: View>: View {
    @Environment(\.commentSheetToolbarConfiguration) private var toolbarConfiguration
    @State private var profileRoute: CommentOwnerProfileRoute?
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .environment(\.openVideoOwnerRouteAction, openProfile)
                .environment(\.openVideoAction, nil)
                .environment(\.openLiveRoomAction, nil)
                .environment(\.openPgcSeasonRouteAction, nil)
                .navigationDestination(item: $profileRoute) { route in
                    UploaderView(
                        owner: route.owner
                    )
                        .environment(\.openVideoAction, nil)
                        .environment(\.openLiveRoomAction, nil)
                        .environment(\.openPgcSeasonRouteAction, nil)
                        .videoDestinations()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("返回", systemImage: "chevron.left", action: toolbarConfiguration.onDismiss)
                            .tint(.primary)
                            .accessibilityLabel("返回")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("刷新", systemImage: "arrow.clockwise", action: toolbarConfiguration.onRefresh)
                            .tint(.primary)
                            .accessibilityLabel("刷新评论")
                    }
                }
            }
            .toolbar(.visible, for: .navigationBar)
        }

    private func openProfile(_ owner: VideoOwner) {
        guard owner.mid > 0 else { return }

        profileRoute = CommentOwnerProfileRoute(owner: owner)
    }
}
