import Combine
import Foundation
import SwiftUI

enum SearchSortOrder: String, CaseIterable, Identifiable, Hashable {
    case comprehensive
    case mostPlayed
    case newest
    case mostSaved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comprehensive:
            return "综合排序"
        case .mostPlayed:
            return "最多播放"
        case .newest:
            return "最新发布"
        case .mostSaved:
            return "最多收藏"
        }
    }

    var apiValue: String? {
        switch self {
        case .comprehensive:
            return nil
        case .mostPlayed:
            return "click"
        case .newest:
            return "pubdate"
        case .mostSaved:
            return "stow"
        }
    }
}

enum SearchScope: String, CaseIterable, Identifiable, Hashable {
    case comprehensive
    case video
    case bangumi
    case movie
    case article
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comprehensive:
            return "综合内容"
        case .video:
            return "视频"
        case .bangumi:
            return "番剧"
        case .movie:
            return "影视"
        case .article:
            return "专栏"
        case .user:
            return "UP主"
        }
    }

    var systemImage: String {
        switch self {
        case .comprehensive:
            return "magnifyingglass"
        case .video:
            return "play.rectangle"
        case .bangumi:
            return "play.tv"
        case .movie:
            return "film"
        case .article:
            return "doc.text"
        case .user:
            return "person.crop.circle"
        }
    }

    var supportsOrder: Bool {
        self == .comprehensive || self == .video
    }
}

enum SearchResultItem: Identifiable, Hashable {
    case video(VideoItem)
    case user(SearchUserItem)
    case bangumi(SearchMediaItem)
    case movie(SearchMediaItem)
    case article(SearchArticleItem)

    var id: String {
        switch self {
        case .video(let video):
            return "video-\(video.id)"
        case .user(let user):
            return "user-\(user.id)"
        case .bangumi(let media):
            return "bangumi-\(media.id)"
        case .movie(let media):
            return "movie-\(media.id)"
        case .article(let article):
            return "article-\(article.id)"
        }
    }

    var sectionTitle: String {
        switch self {
        case .video:
            return "视频"
        case .user:
            return "UP主"
        case .bangumi:
            return "番剧"
        case .movie:
            return "影视"
        case .article:
            return "专栏"
        }
    }

    var sectionSystemImage: String {
        switch self {
        case .video:
            return "play.rectangle"
        case .user:
            return "person.crop.circle"
        case .bangumi:
            return "play.tv"
        case .movie:
            return "film"
        case .article:
            return "doc.text"
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedScope: SearchScope = .comprehensive
    @Published var selectedOrder: SearchSortOrder = .comprehensive
    @Published var hotSearches: [HotSearchItem] = []
    @Published var suggestions: [SearchSuggestItem] = []
    @Published var results: [SearchResultItem] = []
    @Published var state: LoadingState = .idle
    @Published var hotSearchState: LoadingState = .idle
    private(set) var hotSearchesRevision = 0
    private(set) var suggestionsRevision = 0
    private(set) var resultsRevision = 0

    private let api: BiliAPIClient
    private let debouncer = TaskDebouncer()
    private var page = 1
    private var lastKeyword = ""
    private var hasMore = false
    private var searchGeneration = 0

    init(api: BiliAPIClient) {
        self.api = api
    }

    var showsDiscovery: Bool {
        results.isEmpty && lastKeyword.isEmpty
    }

    var showsSuggestions: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && lastKeyword.isEmpty
            && !suggestions.isEmpty
    }

    var showsEmptyResults: Bool {
        results.isEmpty && !lastKeyword.isEmpty && state == .loaded
    }

    var searchPrompt: String {
        selectedScope == .comprehensive ? "搜索" : "搜索\(selectedScope.title)"
    }

    var emptyResultsTitle: String {
        selectedScope == .comprehensive ? "没有找到相关内容" : "没有找到\(selectedScope.title)"
    }

    func loadHotSearch() async {
        guard !hotSearchState.isLoading else { return }
        hotSearchState = .loading
        do {
            updateHotSearches(try await api.fetchHotSearch())
            hotSearchState = .loaded
        } catch {
            hotSearchState = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
    }

    func restoreDiscoveryState(loadHotSearches: Bool = true) async {
        guard showsDiscovery else { return }

        guard loadHotSearches else { return }
        guard hotSearches.isEmpty, hotSearchState != .loaded else { return }
        await loadHotSearch()
    }

    func queryChanged() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            debouncer.cancel()
            invalidateSearchRequests()
            updateSuggestions([])
            updateResults([])
            lastKeyword = ""
            hasMore = false
            state = .idle
            return
        }
        if term != lastKeyword {
            invalidateSearchRequests()
            updateResults([])
            lastKeyword = ""
            hasMore = false
            state = .idle
        }
        debouncer.schedule { [weak self] in
            await self?.loadSuggestions(term: term)
        }
    }

    func clearQuery() {
        debouncer.cancel()
        invalidateSearchRequests()
        query = ""
        updateSuggestions([])
        updateResults([])
        lastKeyword = ""
        hasMore = false
        state = .idle
    }

    func search(_ keyword: String? = nil) async {
        let term = (keyword ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        debouncer.cancel()
        let generation = beginSearchRequest()
        query = term
        page = 1
        lastKeyword = term
        hasMore = false
        updateSuggestions([])
        state = .loading
        do {
            let fetched = try await fetchResults(keyword: term, page: page)
            guard generation == searchGeneration else { return }
            updateResults(fetched)
            hasMore = !fetched.isEmpty
            state = .loaded
        } catch {
            guard generation == searchGeneration else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func searchHotSearch(_ item: HotSearchItem) async {
        selectedScope = .comprehensive
        selectedOrder = .comprehensive
        await search(item.keyword)
    }

    func searchSuggestion(_ item: SearchSuggestItem) async {
        await search(item.value)
    }

    func selectScope(_ scope: SearchScope, animation: Animation? = nil) async {
        guard selectedScope != scope else { return }
        if let animation {
            withAnimation(animation) {
                selectedScope = scope
            }
        } else {
            selectedScope = scope
        }
        guard !lastKeyword.isEmpty else { return }
        await search(lastKeyword)
    }

    func selectOrder(_ order: SearchSortOrder) async {
        guard selectedOrder != order else { return }
        selectedOrder = order
        guard selectedScope.supportsOrder, !lastKeyword.isEmpty else { return }
        await search(lastKeyword)
    }

    func loadMoreIfNeeded(current item: SearchResultItem?) async {
        guard let item,
            results.last?.id == item.id,
            !state.isLoading,
            !lastKeyword.isEmpty,
            hasMore
        else { return }
        let generation = searchGeneration
        let keyword = lastKeyword
        let nextPage = page + 1
        page = nextPage
        state = .loading
        do {
            let more = try await fetchResults(keyword: keyword, page: nextPage)
            guard generation == searchGeneration else { return }
            if more.isEmpty {
                hasMore = false
            }
            appendUnique(more)
            state = .loaded
        } catch {
            guard generation == searchGeneration else { return }
            page = max(1, page - 1)
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchResults(keyword: String, page: Int) async throws -> [SearchResultItem] {
        switch selectedScope {
        case .comprehensive:
            let videos = try await api.searchVideos(keyword: keyword, page: page, order: selectedOrder.apiValue)
                .map(SearchResultItem.video)
            guard page == 1 else { return videos }
            async let userResults = api.searchUsers(keyword: keyword, page: 1)
            async let bangumiResults = api.searchBangumi(keyword: keyword, page: 1)
            async let movieResults = api.searchMovies(keyword: keyword, page: 1)
            async let articleResults = api.searchArticles(keyword: keyword, page: 1)
            let users = ((try? await userResults) ?? [])
                .prefix(3)
                .map(SearchResultItem.user)
            let bangumi = ((try? await bangumiResults) ?? [])
                .prefix(2)
                .map(SearchResultItem.bangumi)
            let movies = ((try? await movieResults) ?? [])
                .prefix(2)
                .map(SearchResultItem.movie)
            let articles = ((try? await articleResults) ?? [])
                .prefix(3)
                .map(SearchResultItem.article)
            return users + bangumi + movies + articles + videos
        case .video:
            return try await api.searchVideos(keyword: keyword, page: page, order: selectedOrder.apiValue)
                .map(SearchResultItem.video)
        case .bangumi:
            return try await api.searchBangumi(keyword: keyword, page: page)
                .map(SearchResultItem.bangumi)
        case .movie:
            return try await api.searchMovies(keyword: keyword, page: page)
                .map(SearchResultItem.movie)
        case .article:
            return try await api.searchArticles(keyword: keyword, page: page)
                .map(SearchResultItem.article)
        case .user:
            return try await api.searchUsers(keyword: keyword, page: page)
                .map(SearchResultItem.user)
        }
    }

    private func loadSuggestions(term: String) async {
        do {
            let fetched = try await api.fetchSearchSuggest(term: term)
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == term else { return }
            updateSuggestions(fetched)
        } catch {
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == term else { return }
            updateSuggestions([])
        }
    }

    private func appendUnique(_ more: [SearchResultItem]) {
        let existing = Set(results.map(\.id))
        let uniqueItems = more.filter { !existing.contains($0.id) }
        guard !uniqueItems.isEmpty else { return }
        results.append(contentsOf: uniqueItems)
        resultsRevision &+= 1
    }

    private func updateHotSearches(_ values: [HotSearchItem]) {
        guard hotSearches != values else { return }
        hotSearches = values
        hotSearchesRevision &+= 1
    }

    private func updateSuggestions(_ values: [SearchSuggestItem]) {
        guard suggestions != values else { return }
        suggestions = values
        suggestionsRevision &+= 1
    }

    private func updateResults(_ values: [SearchResultItem]) {
        guard results != values else { return }
        results = values
        resultsRevision &+= 1
    }

    private func beginSearchRequest() -> Int {
        invalidateSearchRequests()
        return searchGeneration
    }

    private func invalidateSearchRequests() {
        searchGeneration &+= 1
    }
}
