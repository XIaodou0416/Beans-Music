import SwiftUI

struct AccountLibraryListPage: View {
    let kind: AccountLibraryKind
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        List {
            Section {
                content
            }
        }
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!sessionStore.isLoggedIn || state.isLoading)
            }
        }
        .task {
            await loadIfNeeded()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            LibraryEmptyRow(title: kind.loggedOutTitle, systemImage: kind.systemImage)
        } else if items.isEmpty && state.isLoading {
            LibraryLoadingRow(title: kind.loadingTitle)
        } else if items.isEmpty, case .failed(let message) = state {
            LibraryErrorRow(title: kind.errorTitle, message: message) {
                Task { await reload() }
            }
        } else if kind == .favorites {
            favoriteFolderContent
        } else if items.isEmpty {
            LibraryEmptyRow(title: kind.emptyTitle, systemImage: kind.systemImage)
        } else {
            ForEach(items) { item in
                VideoRouteLink(item.videoItem) {
                    LibraryVideoRow(item: item, timestampTitle: kind.timestampTitle)
                }
                .task {
                    await loadMoreIfNeeded(current: item)
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: kind.loadingTitle)
            } else if loadMoreState.isLoading {
                LibraryLoadingRow(title: kind.loadMoreTitle)
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: kind.errorTitle, message: message) {
                    Task { await reload() }
                }
            } else if case .failed(let message) = loadMoreState {
                LibraryErrorRow(title: kind.loadMoreErrorTitle, message: message) {
                    Task { await loadMore() }
                }
            } else if hasMore {
                LibraryLoadMoreTriggerRow(title: kind.loadMoreTitle) {
                    Task { await loadMore() }
                }
            }
        }
    }

    @ViewBuilder
    private var favoriteFolderContent: some View {
        if favoriteFolders.isEmpty {
            LibraryEmptyRow(title: kind.emptyTitle, systemImage: kind.systemImage)
        } else {
            ForEach(favoriteFolders) { folder in
                NavigationLink {
                    FavoriteFolderContentPage(folder: folder, viewModel: viewModel)
                } label: {
                    FavoriteFolderRow(folder: folder)
                }
            }
        }
    }

    private var items: [AccountVideoEntry] {
        switch kind {
        case .history:
            return viewModel.accountHistory
        case .favorites:
            return viewModel.accountFavorites
        case .watchLater:
            return viewModel.accountWatchLater
        }
    }

    private var state: LoadingState {
        switch kind {
        case .history:
            return viewModel.historyState
        case .favorites:
            return viewModel.favoriteState
        case .watchLater:
            return viewModel.watchLaterState
        }
    }

    private var favoriteFolders: [FavoriteFolder] {
        viewModel.favoriteFolders
    }

    private var loadMoreState: LoadingState {
        switch kind {
        case .history:
            return viewModel.historyLoadMoreState
        case .favorites, .watchLater:
            return .idle
        }
    }

    private var hasMore: Bool {
        switch kind {
        case .history:
            return viewModel.historyHasMore
        case .favorites, .watchLater:
            return false
        }
    }

    private func loadIfNeeded() async {
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        switch kind {
        case .history:
            await viewModel.refreshHistory()
        case .favorites:
            await viewModel.refreshFavorites()
        case .watchLater:
            await viewModel.refreshWatchLater()
        }
    }

    private func loadMoreIfNeeded(current item: AccountVideoEntry) async {
        switch kind {
        case .history:
            await viewModel.loadMoreHistoryIfNeeded(current: item)
        case .favorites, .watchLater:
            break
        }
    }

    private func loadMore() async {
        switch kind {
        case .history:
            await viewModel.loadMoreHistory()
        case .favorites, .watchLater:
            break
        }
    }
}
