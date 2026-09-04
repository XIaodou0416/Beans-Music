import Foundation

// MARK: - 下载音质

/// 下载复用第三方音源音质枚举，但与播放音质使用不同的 UserDefaults key。
typealias DownloadQuality = ThirdPartyAudioQuality

extension ThirdPartyAudioQuality {
    static var low: Self { .kb128 }
    static var high: Self { .kb320 }
    static var lossless: Self { .flac }

    var label: String { displayName }

    /// 网易云 player/url 的 level 参数。
    var neteaseLevel: String {
        switch self {
        case .kb128: return "standard"
        case .kb320: return "exhigh"
        case .flac: return "lossless"
        case .flac24bit, .hires, .atmos, .atmosPlus, .master: return "hires"
        }
    }

    /// QQ vkey 的 br 参数。高于 FLAC 的档位使用无损请求，第三方接口仍会
    /// 收到原始质量名称并负责按能力降级。
    var qqBR: String {
        switch self {
        case .kb128: return "M500"
        case .kb320: return "M800"
        case .flac, .flac24bit, .hires, .atmos, .atmosPlus, .master: return "F000"
        }
    }

    /// 酷狗官方接口所能理解的质量档位。
    var beansQuality: BeansAudioQuality {
        switch self {
        case .kb128: return .standard
        case .kb320: return .exhigh
        case .flac: return .lossless
        case .flac24bit, .hires, .atmos, .atmosPlus, .master: return .hires
        }
    }

    var defaultFileExtension: String {
        switch self {
        case .kb128, .kb320: return "mp3"
        case .flac, .flac24bit, .hires, .atmos, .atmosPlus, .master: return "flac"
        }
    }
}

/// 下载结果（downgraded 表示目标音质不可用，已自动降级）
struct DownloadResult {
    let url: URL
    let requestedQuality: DownloadQuality
    let actualQuality: DownloadQuality
    let downgraded: Bool
    let sourceName: String?
}

struct ResolvedDownloadURL {
    let url: URL
    let actualQuality: DownloadQuality
    let sourceName: String?
}

// MARK: - 歌曲下载

/// 下载歌曲到临时目录（不自动保存到本地）：下载完成后交给播放页弹原生分享，由用户自行选择保存或转发
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    private init() {}

    @discardableResult
    func download(song: Song, quality: DownloadQuality) async -> Result<DownloadResult, Error> {
        let chain = quality.fallbackChain
        var lastError: Error = NetEaseError.unknown("下载失败")
        BeansLogger.shared.log(
            "下载开始：\(song.name) 平台=\(song.source.rawValue) 请求音质=\(quality.rawValue)",
            level: .info
        )

        for (index, current) in chain.enumerated() {
            // 1) 解析播放地址（与播放共用同一套接口，仅指定当前下载音质）
            guard let resolved = await resolveURL(song: song, quality: current) else {
                lastError = NetEaseError.unknown("无法解析播放地址（可能为 VIP 歌曲或音源不可用）")
                continue
            }

            // 2) 下载到临时文件
            let tempURL: URL
            let response: URLResponse
            do {
                let request = downloadRequest(for: resolved.url, song: song)
                let (downloaded, downloadResponse) = try await URLSession.shared.download(for: request)
                response = downloadResponse
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    lastError = NetEaseError.unknown("下载失败（HTTP \(http.statusCode)）")
                    continue
                }
                guard isUsableAudioFile(at: downloaded, response: response) else {
                    lastError = NetEaseError.unknown("返回内容不是有效音频")
                    BeansLogger.shared.log(
                        "下载音频校验失败，继续尝试降级：\(song.name) 平台=\(song.source.rawValue) 音质=\(current.rawValue) MIME=\(response.mimeType ?? "未知")",
                        level: .debug
                    )
                    try? FileManager.default.removeItem(at: downloaded)
                    continue
                }
                tempURL = downloaded
            } catch {
                lastError = NetEaseError.unknown("下载失败：\(error.localizedDescription)")
                continue
            }

            // 3) 保存到临时目录（不占用户存储；分享面板自带「存储到文件 / 转发」选项）
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("BeansShare", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safeName = "\(song.name) - \(song.artists)"
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let actualQuality = resolved.actualQuality
            let ext = fileExtension(for: resolved.url, response: response, quality: actualQuality)
            let dest = dir.appendingPathComponent("\(safeName).\(ext)")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
            } catch {
                lastError = NetEaseError.unknown("保存失败：\(error.localizedDescription)")
                continue
            }
            let downgraded = index > 0 || actualQuality != quality
            BeansLogger.shared.log(
                "下载成功：\(song.name) 平台=\(song.source.rawValue) 请求音质=\(quality.rawValue) 实际音质=\(actualQuality.rawValue) 降级=\(downgraded ? "是" : "否") 地址=\(safeURLSummary(resolved.url))",
                level: .info
            )
            return .success(
                DownloadResult(
                    url: dest,
                    requestedQuality: quality,
                    actualQuality: actualQuality,
                    downgraded: downgraded,
                    sourceName: resolved.sourceName
                )
            )
        }
        BeansLogger.shared.log(
            "下载失败：\(song.name) 平台=\(song.source.rawValue) 请求音质=\(quality.rawValue) 所有候选质量均失败",
            level: .error
        )
        return .failure(lastError)
    }

    private func resolveURL(song: Song, quality: DownloadQuality) async -> ResolvedDownloadURL? {
        // 下载优先复用已配置的第三方音源，避免播放能用第三方而下载仍走官方地址。
        let thirdPartyID = song.source == .netease ? song.id : 0
        let thirdPartyKugouID = song.kugouHash ?? song.kugouAlbumAudioId
        if let resolved = await UnblockService.resolve(
            name: song.name,
            artists: song.artists,
            neteaseID: thirdPartyID,
            songSource: song.source,
            qqMid: song.qqMid,
            qqMediaMid: song.qqMediaMid,
            kugouID: thirdPartyKugouID,
            quality: quality
        ) {
            BeansLogger.shared.log(
                "下载使用第三方音源：\(song.name) 来源=\(resolved.source) 请求音质=\(quality.rawValue) 实际音质=\(resolved.quality.rawValue)",
                level: .info
            )
            return ResolvedDownloadURL(
                url: resolved.url,
                actualQuality: resolved.quality,
                sourceName: resolved.source
            )
        }

        if UnblockSourceStore.singleSourceMode {
            return nil
        }

        if song.source == .qq, let mid = song.qqMid {
            guard let result = try? await QQMusicAPI.shared.songURLResult(
                songmid: mid,
                mediaMid: song.qqMediaMid,
                quality: quality.beansQuality
            ),
            let url = URL(string: result.url) else { return nil }
            return ResolvedDownloadURL(
                url: url,
                actualQuality: Self.downloadQuality(forQQBR: result.br),
                sourceName: nil
            )
        } else if song.source == .kugou {
            guard let urlString = try? await KugouMusicAPI.shared.songURL(song: song, quality: quality.beansQuality),
                  let url = URL(string: urlString) else { return nil }
            return ResolvedDownloadURL(url: url, actualQuality: quality, sourceName: nil)
        } else {
            let urls = try? await NetEaseAPI.shared.songURLs(ids: [song.id], level: quality.neteaseLevel)
            guard let urlString = urls?[song.id], let url = URL(string: urlString) else { return nil }
            return ResolvedDownloadURL(url: url, actualQuality: quality, sourceName: nil)
        }
    }

    private func downloadRequest(for url: URL, song: Song) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:80.0) Gecko/20100101 Firefox/80.0", forHTTPHeaderField: "User-Agent")

        if isQQHost(url.host) {
            request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
            let cookie = QQMusicAuth.shared.cookieHeader
            if !cookie.isEmpty {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
        } else if url.host?.lowercased().contains("kugou") == true
                    || url.host?.lowercased().contains("kgimg.com") == true {
            request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
            let cookie = KugouMusicAuth.shared.cookieHeader
            if !cookie.isEmpty {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
        }
        return request
    }

    private func isQQHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host.contains("qq.com")
            || host.contains("qqmusic")
            || host.contains("ptqqmusic")
            || host.contains("gitv.tv")
    }

    private static func downloadQuality(forQQBR br: String) -> DownloadQuality {
        switch br.uppercased() {
        case "M500": return .kb128
        case "M800": return .kb320
        case "C400": return .kb320
        case "F000": return .flac
        default: return .kb128
        }
    }

    private func fileExtension(for url: URL, response: URLResponse, quality: DownloadQuality) -> String {
        if let mimeType = response.mimeType?.lowercased() {
            if mimeType.contains("flac") { return "flac" }
            if mimeType.contains("mpeg") || mimeType.contains("mp3") { return "mp3" }
            if mimeType.contains("mp4") || mimeType.contains("m4a") { return "m4a" }
            if mimeType.contains("aac") { return "aac" }
            if mimeType.contains("ogg") { return "ogg" }
            if mimeType.contains("wav") { return "wav" }
        }

        let knownExtensions = Set(["mp3", "m4a", "flac", "aac", "ogg", "wav"])
        let urlExtension = url.pathExtension.lowercased()
        if knownExtensions.contains(urlExtension) {
            return urlExtension
        }
        if let suggestedFilename = response.suggestedFilename,
           let responseExtension = suggestedFilename.split(separator: ".").last.map({ String($0).lowercased() }),
           knownExtensions.contains(responseExtension) {
            return responseExtension
        }
        return quality.defaultFileExtension
    }

    /// 防止接口返回 HTTP 200 的 JSON/HTML 错误页被保存为歌曲，并阻断音质降级。
    private func isUsableAudioFile(at url: URL, response: URLResponse) -> Bool {
        if let mimeType = response.mimeType?.lowercased(),
           mimeType.contains("text/") || mimeType.contains("json") || mimeType.contains("html") {
            return false
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value > 1024 else {
            return false
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 64)) ?? Data()
        guard !prefix.isEmpty else { return false }
        let text = String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return !text.hasPrefix("{")
            && !text.hasPrefix("[")
            && !text.hasPrefix("<html")
            && !text.hasPrefix("<!doctype")
    }

    private func safeURLSummary(_ url: URL) -> String {
        let host = url.host ?? "?"
        let path = url.path.isEmpty ? "/" : url.path
        let shortPath = path.count > 64 ? String(path.prefix(64)) + "..." : path
        return "\(host)\(shortPath)"
    }
}
