import SwiftUI

struct DynamicView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        DynamicContentRoot(
            api: dependencies.api,
            libraryStore: libraryStore,
            sessionStore: dependencies.sessionStore
        )
    }
}

private struct DynamicContentRoot: View {
    let api: BiliAPIClient
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var holder = DynamicViewModelHolder()
    @StateObject private var pullRefreshSettings = PullRefreshRuntimeSettingsStore()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                DynamicFeedScreenContent(
                    api: api,
                    viewModel: viewModel,
                    isLoggedIn: sessionStore.isLoggedIn,
                    pullRefreshTriggerDistance: CGFloat(pullRefreshSettings.triggerDistance)
                )
            } else {
                DynamicInitialFeedContent(isLoggedIn: sessionStore.isLoggedIn)
                    .task {
                        holder.configure(
                            api: api,
                            libraryStore: libraryStore,
                            sessionStore: sessionStore
                        )
                    }
            }
        }
        .task {
            pullRefreshSettings.bind(libraryStore)
        }
        .onChange(of: DynamicFeedAccountContext(
            mainCredentialVersion: sessionStore.playbackCredentialVersion,
            dynamicFeedCredentialVersion: sessionStore.dynamicFeedAccountCredentialVersion,
            multiAccountExperimentEnabled: libraryStore.multiAccountExperimentEnabled
        )) { _, _ in
            holder.reconfigure(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore
            )
        }
    }
}

private struct DynamicFeedAccountContext: Equatable {
    let mainCredentialVersion: Int
    let dynamicFeedCredentialVersion: Int
    let multiAccountExperimentEnabled: Bool
}

extension View {
    @ViewBuilder
    func dynamicLoadMoreTask<ID: Equatable>(
        if condition: Bool,
        id: ID,
        action: @escaping () async -> Void
    ) -> some View {
        if condition {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}
