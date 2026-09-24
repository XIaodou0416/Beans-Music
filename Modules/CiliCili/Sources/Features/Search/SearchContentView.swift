import SwiftUI

struct SearchContentView: View {
    @ObservedObject var viewModel: SearchViewModel
    let showsHotSearches: Bool
    @ObservedObject var accessoryStore: SearchBottomAccessoryStore

    var body: some View {
        SearchListView(
            viewModel: viewModel,
            showsHotSearches: showsHotSearches
        )
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.results.isEmpty {
                ErrorStateView(title: "搜索失败", message: message) {
                    Task { await viewModel.search() }
                }
            }
        }
        .task(id: viewModel.showsDiscovery) {
            accessoryStore.attach(viewModel)
            await loadDiscoveryStateIfNeeded()
        }
        .onDisappear {
            accessoryStore.isSearchFocused = false
            accessoryStore.isKeyboardVisible = false
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                SearchFilterCapsule(viewModel: viewModel)
            }
        }
    }

    private func loadDiscoveryStateIfNeeded() async {
        await viewModel.restoreDiscoveryState(loadHotSearches: showsHotSearches)
    }
}

struct SearchTabBottomAccessory: View {
    @ObservedObject var store: SearchBottomAccessoryStore

    @ViewBuilder
    var body: some View {
        if let viewModel = store.viewModel {
            SearchFilterCapsule(viewModel: viewModel)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 16)
        }
    }
}

private struct SearchFilterCapsule: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        HStack(spacing: 0) {
            scopeMenu
            orderMenu
        }
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 40)
        .foregroundStyle(.primary)
    }

    private var scopeMenu: some View {
        Menu {
            ForEach(SearchScope.allCases) { scope in
                Button {
                    Task {
                        await viewModel.selectScope(scope, animation: .smooth(duration: 0.28))
                    }
                } label: {
                    Label(
                        scope.title,
                        systemImage: scope == viewModel.selectedScope
                            ? "checkmark"
                            : scope.systemImage
                    )
                }
            }
        } label: {
            filterLabel(title: viewModel.selectedScope.title)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityLabel("搜索类型")
        .accessibilityValue(viewModel.selectedScope.title)
    }

    private var orderMenu: some View {
        Menu {
            ForEach(SearchSortOrder.allCases) { order in
                Button {
                    Task { await viewModel.selectOrder(order) }
                } label: {
                    Label(
                        order.title,
                        systemImage: order == viewModel.selectedOrder
                            ? "checkmark"
                            : "arrow.up.arrow.down"
                    )
                }
            }
        } label: {
            filterLabel(title: viewModel.selectedOrder.title)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
        .disabled(!viewModel.selectedScope.supportsOrder)
        .foregroundStyle(viewModel.selectedScope.supportsOrder ? .primary : .secondary)
        .accessibilityLabel("排序方式")
        .accessibilityValue(viewModel.selectedOrder.title)
    }

    private func filterLabel(title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
    }
}
