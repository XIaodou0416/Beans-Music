import Combine
import Foundation

@MainActor
final class SearchViewModelHolder: ObservableObject {
    @Published var viewModel: SearchViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: SearchRenderSnapshot?

    func configure(api: BiliAPIClient) {
        if viewModel == nil {
            let viewModel = SearchViewModel(api: api)
            self.viewModel = viewModel
            lastSnapshot = SearchRenderSnapshot(viewModel)
            cancellable = viewModel.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self, weak viewModel] in
                    guard let self, let viewModel else { return }
                    let snapshot = SearchRenderSnapshot(viewModel)
                    guard snapshot != self.lastSnapshot else { return }
                    self.lastSnapshot = snapshot
                    self.objectWillChange.send()
                }
            }
        }
    }
}

@MainActor
final class SearchBottomAccessoryStore: ObservableObject {
    @Published private(set) var viewModel: SearchViewModel?
    @Published var isSearchFocused = false
    @Published var isKeyboardVisible = false

    var usesKeyboardControls: Bool {
        isSearchFocused && isKeyboardVisible
    }

    func attach(_ viewModel: SearchViewModel) {
        guard self.viewModel !== viewModel else { return }
        self.viewModel = viewModel
    }
}

private struct SearchRenderSnapshot: Equatable {
    let query: String
    let showsDiscovery: Bool
    let selectedScope: SearchScope
    let selectedOrder: SearchSortOrder
    let state: LoadingState
    let hotSearchState: LoadingState
    let hotSearchCount: Int
    let hotSearchRevision: Int
    let suggestionCount: Int
    let suggestionRevision: Int
    let resultCount: Int
    let firstResultID: String?
    let lastResultID: String?
    let resultRevision: Int

    init(_ viewModel: SearchViewModel) {
        query = viewModel.query
        showsDiscovery = viewModel.showsDiscovery
        selectedScope = viewModel.selectedScope
        selectedOrder = viewModel.selectedOrder
        state = viewModel.state
        hotSearchState = viewModel.hotSearchState
        hotSearchCount = viewModel.hotSearches.count
        hotSearchRevision = viewModel.hotSearchesRevision
        suggestionCount = viewModel.suggestions.count
        suggestionRevision = viewModel.suggestionsRevision
        resultCount = viewModel.results.count
        firstResultID = viewModel.results.first?.id
        lastResultID = viewModel.results.last?.id
        resultRevision = viewModel.resultsRevision
    }
}
