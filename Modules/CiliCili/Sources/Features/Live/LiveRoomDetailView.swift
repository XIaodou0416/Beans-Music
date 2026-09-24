import SwiftUI

struct LiveRoomDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let seedRoom: LiveRoom
    @StateObject private var holder = LiveRoomViewModelHolder()

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: .constant(false),
            background: VideoDetailTheme.background,
            navigationBarVisibility: .hidden,
            hidesBackButton: true,
            statusBarStyle: statusBarStyle,
            performanceContext: .live(seedRoom),
            lifecycleActions: pageLifecycleActions
        ) {
            PlaybackDetailLoadedStatePage(
                holder.viewModel,
                performanceContext: .live(seedRoom)
            ) { viewModel in
                LiveRoomShellRepresentable(
                    viewModel: viewModel,
                    onNavigateBack: { dismiss() }
                )
                .ignoresSafeArea()
            } initialContent: {
                LiveRoomInitialPlaceholder(room: seedRoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: seedRoom.id) {
            configureAndStartPlaybackIfNeeded()
        }
    }

    private var pageLifecycleActions: PlaybackDetailPageLifecycleActions {
        PlaybackDetailPageLifecycleActions(
            onAppear: {
                holder.viewModel?.resumePlaybackAfterCoveredNavigationIfNeeded()
            },
            onScenePhaseChanged: { phase in
                guard let viewModel = holder.viewModel else { return }
                switch phase {
                case .active:
                    viewModel.resumeLiveDanmakuIfNeeded()
                case .background:
                    viewModel.suspendLiveDanmaku()
                default:
                    break
                }
            },
            onDisappear: {
                holder.viewModel?.stopPlaybackForNavigation()
            }
        )
    }

    private var statusBarStyle: UIStatusBarStyle {
        guard colorScheme != .dark else {
            return .lightContent
        }
        return .darkContent
    }

    private func configureAndStartPlaybackIfNeeded() {
        holder.configure(
            room: seedRoom,
            api: dependencies.api,
            libraryStore: dependencies.libraryStore
        )
        holder.viewModel?.resumePlaybackAfterCoveredNavigationIfNeeded()
    }

}
