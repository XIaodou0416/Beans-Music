import Foundation
import OSLog

nonisolated final class BiliAPIClient: @unchecked Sendable {
    let baseURL = URL(string: "https://api.bilibili.com")!
    let appURL = URL(string: "https://app.bilibili.com")!
    let commentURL = URL(string: "https://comment.bilibili.com")!
    static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let webUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    let session: URLSession
    let sessionStore: SessionStore
    let libraryStore: LibraryStore
    let homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore
    let playURLCache: PlayURLCache
    let webPagePlayInfoStreamFetch: @Sendable (URLRequest, Float) async throws -> BiliWebPagePlayInfoStreamResult
    let state = BiliAPIClientState()
    static let uploaderLogger = Logger(subsystem: "cc.bili", category: "Uploader")

    init(
        session: URLSession = .shared,
        sessionStore: SessionStore,
        libraryStore: LibraryStore,
        homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore,
        playURLCache: PlayURLCache = .shared,
        webPagePlayInfoStreamFetch: @escaping @Sendable (URLRequest, Float) async throws
            -> BiliWebPagePlayInfoStreamResult = { request, priority in
                try await BiliWebPagePlayInfoStreamingSession.shared.fetch(
                    request: request,
                    priority: priority
                )
            }
    ) {
        self.session = session
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.homeRecommendDiagnosticsStore = homeRecommendDiagnosticsStore
        self.playURLCache = playURLCache
        self.webPagePlayInfoStreamFetch = webPagePlayInfoStreamFetch
    }

}

extension JSONDecoder {
    nonisolated static var bili: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}
