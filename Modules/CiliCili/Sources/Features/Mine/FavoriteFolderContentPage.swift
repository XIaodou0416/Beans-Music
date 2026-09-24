import SwiftUI

struct FavoriteFolderContentPage: View {
    let folder: FavoriteFolder
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        List {
            Section {
                content
            } header: {
                if let count = folder.mediaCount {
                    Text("\(count) 个内容")
                }
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
            LibraryEmptyRow(title: "登录后同步账号收藏", systemImage: "star")
        } else if items.isEmpty && state.isLoading {
            LibraryLoadingRow(title: "正在同步收藏夹")
        } else if items.isEmpty, case .failed(let message) = state {
            LibraryErrorRow(title: "收藏夹同步失败", message: message) {
                Task { await reload() }
            }
        } else if items.isEmpty {
            LibraryEmptyRow(title: "这个收藏夹还没有视频", systemImage: "folder")
        } else {
            ForEach(items) { item in
                VideoRouteLink(item.videoItem) {
                    LibraryVideoRow(item: item, timestampTitle: "收藏时间")
                }
                .task {
                    await viewModel.loadMoreFavoriteFolderIfNeeded(folder, current: item)
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: "正在同步收藏夹")
            } else if loadMoreState.isLoading {
                LibraryLoadingRow(title: "正在加载更多收藏")
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: "收藏夹同步失败", message: message) {
                    Task { await reload() }
                }
            } else if case .failed(let message) = loadMoreState {
                LibraryErrorRow(title: "更多收藏加载失败", message: message) {
                    Task { await viewModel.loadMoreFavoriteFolder(folder) }
                }
            } else if hasMore {
                LibraryLoadMoreTriggerRow(title: "正在加载更多收藏") {
                    Task { await viewModel.loadMoreFavoriteFolder(folder) }
                }
            }
        }
    }

    private var items: [AccountVideoEntry] {
        viewModel.favoriteFolderEntries[folder.id] ?? []
    }

    private var state: LoadingState {
        viewModel.favoriteFolderEntryStates[folder.id] ?? .idle
    }

    private var loadMoreState: LoadingState {
        viewModel.favoriteFolderLoadMoreStates[folder.id] ?? .idle
    }

    private var hasMore: Bool {
        viewModel.favoriteFolderHasMore[folder.id] == true
    }

    private func loadIfNeeded() async {
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        await viewModel.refreshFavoriteFolder(folder)
    }
}
