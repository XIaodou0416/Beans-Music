import SwiftUI
import UIKit
import WebKit
import CoreImage.CIFilterBuiltins

/// Hosts the bundled visual player page and connects it to the native playback bridge.
/// The page owns its layout and interaction; Beans supplies account, catalog and playback data.
struct MineradioRestoredView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            MineradioRestoredWebView()
                .ignoresSafeArea()

            Button {
                BeansHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 12)
            .accessibilityLabel("关闭播放器")
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .onAppear { BeansOrientationLock.shared.setEmbeddedPlayerOrientation() }
        .onDisappear { BeansOrientationLock.shared.restoreDefaultOrientation() }
    }
}

struct MineradioRestoredWebView: UIViewRepresentable {
    private func bundledResource(_ name: String, fileExtension: String) -> URL? {
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "MineradioRestored"
        ) {
            return url
        }

        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return url
        }

        guard let resourceRoot = Bundle.main.resourceURL else { return nil }
        let url = resourceRoot
            .appendingPathComponent("MineradioRestored", isDirectory: true)
            .appendingPathComponent("\(name).\(fileExtension)", isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.add(context.coordinator, name: "iosBridge")

        if let bridgeURL = bundledResource("ios-bridge", fileExtension: "js"),
           let bridge = try? String(contentsOf: bridgeURL, encoding: .utf8) {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: bridge,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

        // Apply the mobile shell after the document head is available.
        if let styleURL = bundledResource("ios-style", fileExtension: "js"),
           let style = try? String(contentsOf: styleURL, encoding: .utf8) {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: style,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Keep normal taps and scrolling, but prevent the embedded page from
        // entering WebKit's page-zoom gesture.
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        context.coordinator.webView = webView

        guard let pageURL = bundledResource("index", fileExtension: "html") else {
            return webView
        }
        let accessRoot = pageURL.deletingLastPathComponent()
        webView.loadFileURL(pageURL, allowingReadAccessTo: accessRoot)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let session: URLSession

        override init() {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 25
            session = URLSession(configuration: configuration)
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "iosBridge",
                  let body = message.body as? [String: Any] else { return }

            if let type = body["type"] as? String, type == "native-api",
               let requestID = body["id"] as? String,
               let action = body["action"] as? String {
                let payload = body["payload"] as? [String: Any] ?? [:]
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let data = try await self.perform(action: action, payload: payload)
                        self.resolve(requestID: requestID, value: ["ok": true, "data": data])
                    } catch {
                        self.resolve(requestID: requestID, value: [
                            "ok": false,
                            "error": error.localizedDescription,
                        ])
                    }
                }
                return
            }

            if let type = body["type"] as? String, type == "error" || type == "rejection" {
                let message = body["message"] as? String ?? "unknown web error"
                BeansLogger.shared.log("沉浸式播放器页面错误：\(message.prefix(240))", level: .error)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(
                "window.__mineradioIOSDidFinish && window.__mineradioIOSDidFinish();",
                completionHandler: nil
            )
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            webView.load(URLRequest(url: url))
            return nil
        }

        private func resolve(requestID: String, value: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: value),
                  let json = String(data: data, encoding: .utf8),
                  let idData = try? JSONSerialization.data(withJSONObject: requestID),
                  let idJSON = String(data: idData, encoding: .utf8) else { return }
            let script = "window.__mineradioResolveNativeAPI && window.__mineradioResolveNativeAPI(\(idJSON), \(json));"
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(script, completionHandler: nil)
            }
        }

        private func value(_ payload: [String: Any], _ keys: [String]) -> String {
            for key in keys {
                if let string = payload[key] as? String, !string.isEmpty { return string }
                if let number = payload[key] as? NSNumber { return number.stringValue }
            }
            return ""
        }

        private func integer(_ payload: [String: Any], _ keys: [String]) -> Int {
            for key in keys {
                if let number = payload[key] as? Int { return number }
                if let number = payload[key] as? NSNumber { return number.intValue }
                if let string = payload[key] as? String, let number = Int(string) { return number }
            }
            return 0
        }

        private func timeInterval(_ payload: [String: Any], _ keys: [String]) -> TimeInterval {
            for key in keys {
                if let number = payload[key] as? Double { return number }
                if let number = payload[key] as? NSNumber { return number.doubleValue }
                if let string = payload[key] as? String, let number = Double(string) { return number }
            }
            return 0
        }

        private func beansSessionStatus() async -> [String: Any] {
            let savedAuth = AuthStore()
            var netease: [String: Any] = [
                "provider": "netease",
                "loggedIn": savedAuth.isLoggedIn,
                "uid": savedAuth.user?.uid ?? 0,
                "nickname": savedAuth.user?.nickname ?? "",
                "avatar": savedAuth.user?.avatarURL?.absoluteString ?? "",
                "vipType": savedAuth.user?.vipType ?? 0,
                "vipBadge": savedAuth.user?.vipBadge ?? "",
            ]
            let qq: [String: Any] = [
                "provider": "qq",
                "loggedIn": QQMusicAuth.shared.isLoggedIn,
                "nickname": QQMusicAuth.shared.nickname,
                "vipBadge": QQMusicAuth.shared.vipBadge ?? "",
            ]
            let kugou: [String: Any] = [
                "provider": "kugou",
                "loggedIn": KugouMusicAuth.shared.isLoggedIn,
                "userId": KugouMusicAuth.shared.userId,
                "nickname": KugouMusicAuth.shared.nickname,
                "avatar": KugouMusicAuth.shared.avatarURL?.absoluteString ?? "",
                "vipType": KugouMusicAuth.shared.vipType,
                "vipBadge": KugouMusicAuth.shared.vipBadge ?? "",
            ]
            return [
                "loggedIn": (netease["loggedIn"] as? Bool == true) || QQMusicAuth.shared.isLoggedIn || KugouMusicAuth.shared.isLoggedIn,
                "netease": netease,
                "qq": qq,
                "kugou": kugou,
            ]
        }

        private func audioQuality(from raw: String) -> BeansAudioQuality {
            switch raw.lowercased() {
            case "standard", "normal", "128k": return .standard
            case "exhigh", "high", "320k", "hq": return .exhigh
            case "lossless", "flac", "sq": return .lossless
            case "master", "jymaster", "svip", "hires", "highres": return .hires
            default: return .current
            }
        }

        @MainActor
        private func qrImageDataURL(for text: String) -> String? {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(text.utf8)
            filter.correctionLevel = "M"
            guard let output = filter.outputImage else { return nil }

            let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            let context = CIContext()
            guard let image = context.createCGImage(scaled, from: scaled.extent),
                  let png = UIImage(cgImage: image).pngData() else { return nil }
            return "data:image/png;base64,\(png.base64EncodedString())"
        }

        private func songDictionary(_ song: Song) -> [String: Any] {
            let provider: String
            switch song.source {
            case .netease: provider = "netease"
            case .qq: provider = "qq"
            case .kugou: provider = "kugou"
            }
            var result: [String: Any] = [
                "provider": provider,
                "source": provider,
                "type": "song",
                "id": song.id,
                "name": song.name,
                "title": song.name,
                "artist": song.artists,
                "artists": song.artists.split(separator: "/").map { ["name": String($0).trimmingCharacters(in: .whitespaces)] },
                "album": song.album,
                "cover": song.coverURL?.absoluteString ?? "",
                "duration": Int(song.duration * 1000),
                "fee": song.fee,
                "playable": true,
            ]
            if let qqMid = song.qqMid, !qqMid.isEmpty {
                result["mid"] = qqMid
                result["songmid"] = qqMid
            }
            if let mediaMid = song.qqMediaMid, !mediaMid.isEmpty {
                result["mediaMid"] = mediaMid
                result["media_mid"] = mediaMid
            }
            if let hash = song.kugouHash, !hash.isEmpty {
                result["hash"] = hash
            }
            if let albumAudioID = song.kugouAlbumAudioId, !albumAudioID.isEmpty {
                result["albumAudioId"] = albumAudioID
            }
            if let albumID = song.kugouAlbumId, !albumID.isEmpty {
                result["albumId"] = albumID
            }
            return result
        }

        private func playlistDictionary(_ playlist: Playlist) -> [String: Any] {
            [
                "id": playlist.id,
                "name": playlist.name,
                "trackCount": playlist.trackCount,
                "count": playlist.trackCount,
                "playCount": playlist.playCount,
                "cover": playlist.coverURL?.absoluteString ?? "",
                "coverImgUrl": playlist.coverURL?.absoluteString ?? "",
                "subscribed": false,
                "specialType": playlist.specialType,
            ]
        }

        private func songList(_ songs: [Song]) -> [[String: Any]] {
            songs.map(songDictionary)
        }

        private func playlistList(_ playlists: [Playlist]) -> [[String: Any]] {
            playlists.map(playlistDictionary)
        }

        private func parseCookieHeader(_ raw: String) -> [String: String] {
            raw.split(separator: ";").reduce(into: [String: String]()) { result, item in
                let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !value.isEmpty { result[key] = value }
            }
        }

        private func perform(action: String, payload: [String: Any]) async throws -> [String: Any] {
            switch action {
            case "beans-session-status":
                return await beansSessionStatus()

            case "itunes-search":
                let keyword = value(payload, ["keywords", "term"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { throw NetEaseError.unknown("搜索关键词不能为空") }
                return try await iTunesSearch(keyword: keyword, limit: integer(payload, ["limit"]))

            case "netease-search":
                let keyword = value(payload, ["keywords", "term"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { throw NetEaseError.unknown("搜索关键词不能为空") }
                let songs = try await NetEaseAPI.shared.search(
                    keyword: keyword,
                    limit: max(1, integer(payload, ["limit"]))
                )
                return ["provider": "netease", "songs": songList(songs)]

            case "qq-search":
                let keyword = value(payload, ["keywords", "term"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { throw NetEaseError.unknown("搜索关键词不能为空") }
                let songs = try await QQMusicAPI.shared.searchSongs(
                    keyword: keyword,
                    limit: max(1, integer(payload, ["limit"]))
                )
                return ["provider": "qq", "songs": songList(songs)]

            case "kugou-search":
                let keyword = value(payload, ["keywords", "term"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { throw NetEaseError.unknown("搜索关键词不能为空") }
                let songs = try await KugouMusicAPI.shared.searchSongs(
                    keyword: keyword,
                    limit: max(1, integer(payload, ["limit"]))
                )
                return ["provider": "kugou", "songs": songList(songs)]

            case "netease-song-url":
                let id = integer(payload, ["id"])
                let quality = BeansAudioQuality.current.level
                let info = try await NetEaseAPI.shared.songURLInfo(ids: [id], level: quality)[id]
                let url = info?.url ?? ""
                return [
                    "provider": "netease",
                    "url": url,
                    "playable": !url.isEmpty,
                    "trial": info?.freeTrial ?? false,
                    "level": quality,
                ]

            case "qq-song-url":
                let mid = value(payload, ["mid", "songmid", "id"])
                let mediaMid = value(payload, ["mediaMid", "media_mid"])
                let url = try await QQMusicAPI.shared.songURL(
                    songmid: mid,
                    mediaMid: mediaMid.isEmpty ? nil : mediaMid,
                    quality: .current
                ) ?? ""
                return ["provider": "qq", "url": url, "playable": !url.isEmpty]

            case "kugou-song-url":
                let hash = value(payload, ["hash", "id"])
                let url = try await KugouMusicAPI.shared.songURL(hash: hash, albumAudioId: nil, albumId: nil) ?? ""
                return ["provider": "kugou", "url": url, "playable": !url.isEmpty]

            case "netease-lyric":
                let id = integer(payload, ["id"])
                let lyric = try await NetEaseAPI.shared.lyricWithTranslation(id: id)
                return ["lyric": lyric.lrc ?? "", "tlyric": lyric.tlyric ?? ""]

            case "qq-lyric":
                let lyric = try await QQMusicAPI.shared.lyric(songmid: value(payload, ["mid", "songmid", "id"]))
                return ["lyric": lyric ?? ""]

            case "kugou-lyric":
                let lyric = await KugouMusicAPI.shared.lyric(
                    hash: value(payload, ["hash", "id"]),
                    duration: timeInterval(payload, ["duration"])
                )
                return ["lyric": lyric]

            case "netease-login-qr-key":
                return ["ok": false, "requiresNativeLogin": true, "message": "请先在 Beans Music 原生设置中登录"]

            case "netease-login-qr-check":
                return ["code": 0, "requiresNativeLogin": true, "message": "请先在 Beans Music 原生设置中登录"]

            case "netease-login-status":
                let session = await beansSessionStatus()
                return session["netease"] as? [String: Any]
                    ?? ["provider": "netease", "loggedIn": false]

            case "qq-login-status":
                let auth = QQMusicAuth.shared
                return ["loggedIn": auth.isLoggedIn, "nickname": auth.nickname, "vipBadge": auth.vipBadge ?? ""]

            case "kugou-login-status":
                let auth = KugouMusicAuth.shared
                return [
                    "loggedIn": auth.isLoggedIn,
                    "nickname": auth.nickname,
                    "userId": auth.userId,
                    "avatar": auth.avatarURL?.absoluteString ?? "",
                    "vipType": auth.vipType,
                ]

            case "netease-login-cookie":
                return ["ok": false, "requiresNativeLogin": true, "message": "网页播放器不接收登录会话，请在 Beans Music 原生设置中登录"]

            case "qq-login-cookie":
                return ["ok": false, "requiresNativeLogin": true, "message": "网页播放器不接收登录会话，请在 Beans Music 原生设置中登录"]

            case "netease-user-playlists":
                let user = try await NetEaseAPI.shared.account()
                return ["loggedIn": true, "playlists": playlistList(try await NetEaseAPI.shared.userPlaylists(uid: user.uid))]

            case "netease-playlist-tracks":
                let songs = try await NetEaseAPI.shared.playlistTracks(id: integer(payload, ["id"]))
                return ["tracks": songList(songs), "songs": songList(songs)]

            case "netease-like":
                let id = integer(payload, ["id"])
                let liked = (payload["like"] as? Bool) ?? true
                return ["success": try await NetEaseAPI.shared.like(id: id, liked: liked), "liked": liked]

            case "qq-user-playlists":
                let lists = try await QQMusicAPI.shared.userPlaylists(uin: QQMusicAuth.shared.playlistUin)
                return ["loggedIn": QQMusicAuth.shared.isLoggedIn, "playlists": playlistList(lists)]

            case "qq-playlist-tracks":
                let songs = try await QQMusicAPI.shared.playlistSongs(listID: integer(payload, ["id"]))
                return ["tracks": songList(songs), "songs": songList(songs)]

            case "kugou-user-playlists":
                let lists = try await KugouMusicAPI.shared.userPlaylists()
                return ["loggedIn": KugouMusicAuth.shared.isLoggedIn, "playlists": playlistList(lists)]

            case "kugou-playlist-tracks":
                let songs = try await KugouMusicAPI.shared.playlistSongs(listID: integer(payload, ["id"]))
                return ["tracks": songList(songs), "songs": songList(songs)]

            case "netease-logout":
                NetEaseAPI.shared.clearCookies()
                return ["ok": true, "loggedIn": false]

            case "qq-logout":
                QQMusicAuth.shared.logout()
                return ["ok": true, "loggedIn": false]

            case "kugou-logout":
                KugouMusicAuth.shared.logout()
                return ["ok": true, "loggedIn": false]

            case "qq-web-login":
                return ["ok": false, "requiresNativeLogin": true, "message": "请先在 Beans Music 原生设置中登录"]

            case "kugou-web-login":
                return ["ok": false, "requiresNativeLogin": true, "message": "请先在 Beans Music 原生设置中登录"]

            default:
                return [:]
            }
        }

        private func iTunesSearch(keyword: String, limit: Int) async throws -> [String: Any] {
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems = [
                URLQueryItem(name: "media", value: "music"),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 25))"),
                URLQueryItem(name: "term", value: keyword),
            ]
            let (data, response) = try await session.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetEaseError.network
            }
            return object
        }
    }
}
