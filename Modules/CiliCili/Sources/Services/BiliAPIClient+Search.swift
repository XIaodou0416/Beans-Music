import Foundation

extension BiliAPIClient {
    func searchVideos(keyword: String, page: Int = 1, order: String? = nil) async throws -> [VideoItem] {
        let results: [SearchVideoItem] = try await searchTypedResults(
            keyword: keyword,
            searchType: "video",
            page: page,
            order: order
        )
        return
            results
            .filter { !$0.bvid.isEmpty }
            .map { $0.asVideoItem() }
    }

    func searchUsers(keyword: String, page: Int = 1) async throws -> [SearchUserItem] {
        try await searchTypedResults(keyword: keyword, searchType: "bili_user", page: page)
            .filter { $0.mid > 0 }
    }

    func searchBangumi(keyword: String, page: Int = 1) async throws -> [SearchMediaItem] {
        try await searchTypedResults(keyword: keyword, searchType: "media_bangumi", page: page)
    }

    func searchMovies(keyword: String, page: Int = 1) async throws -> [SearchMediaItem] {
        try await searchTypedResults(keyword: keyword, searchType: "media_ft", page: page)
    }

    func searchArticles(keyword: String, page: Int = 1) async throws -> [SearchArticleItem] {
        try await searchTypedResults(keyword: keyword, searchType: "article", page: page)
            .filter { $0.articleID > 0 }
    }

    private func searchTypedResults<Result: Decodable & Sendable>(
        keyword: String,
        searchType: String,
        page: Int = 1,
        order: String? = nil
    ) async throws -> [Result] {
        let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
        var params = [
            "keyword": keyword,
            "search_type": searchType,
            "page": String(page),
            "page_size": "20",
        ]
        if let order, !order.isEmpty {
            params["order"] = order
        }
        let signed = WBISigner.sign(params, keys: keys)
        let response: BiliResponse<SearchTypeData<Result>> = try await get(
            base: baseURL,
            path: "/x/web-interface/wbi/search/type",
            query: signed,
            responseCachePolicy: .brief
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return response.payload?.result ?? []
    }

    func fetchSearchSuggest(term: String) async throws -> [SearchSuggestItem] {
        let response: BiliResponse<SearchSuggestResponse> = try await get(
            base: baseURL,
            path: "/x/web-interface/search/suggest",
            query: ["term": term, "main_ver": "v1", "highlight": ""],
            responseCachePolicy: .brief
        )
        return response.payload?.tag ?? []
    }

    func fetchHotSearch() async throws -> [HotSearchItem] {
        let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
        let signed = WBISigner.sign(["limit": "10"], keys: keys)
        let response: BiliResponse<HotSearchData> = try await get(
            base: baseURL,
            path: "/x/web-interface/wbi/search/square",
            query: signed,
            responseCachePolicy: .short
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return response.payload?.trending?.list ?? []
    }
}
