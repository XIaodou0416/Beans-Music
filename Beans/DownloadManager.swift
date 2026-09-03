import Foundation

// MARK: - 下载音质

enum DownloadQuality: String, CaseIterable, Identifiable {
    case low
    case high
    case lossless

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "低质量（128kbps）"
        case .high: return "高质量（320kbps）"
        case .lossless: return "无损 FLAC（需 VIP，不可用自动降级）"
        }
    }

    /// 网易云音质档位（player/url v1 level）
    var neteaseLevel: String {
        switch self {
        case .low: return "standard"
        case .high: return "exhigh"
        case .lossless: return "lossless"
        }
    }

    /// QQ 音乐音质档位（F000=FLAC / M800=320k / M500=128k）
    var qqBR: String {
        switch self {
        case .low: return "M500"
        case .high: return "M800"
        case .lossless: return "F000"
        }
    }

    /// 降级链：无损 -> 320k -> 128k；高质量 -> 320k -> 128k
    var fallbackChain: [DownloadQuality] {
        switch self {
        case .lossless: return [.lossless, .high, .low]
        case .high: return [.high, .low]
        case .low: return [.low]
        }
    }
}

/// 下载结果（downgraded 表示目标音质不可用，已自动降级）
struct DownloadResult {
    let url: URL
    let downgraded: Bool
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

        for (index, current) in chain.enumerated() {
            // 1) 解析播放地址（与播放共用同一套接口，仅指定音质）
            guard let urlString = await resolveURL(song: song, quality: current),
                  let url = URL(string: urlString), !urlString.isEmpty else {
                lastError = NetEaseError.unknown("无法解析播放地址（可能为 VIP 歌曲）")
                continue
            }

            // 2) 下载到临时文件
            let tempURL: URL
            do {
                let (downloaded, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    lastError = NetEaseError.unknown("下载失败（HTTP \(http.statusCode)）")
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
            let ext: String
            if song.source == .qq {
                ext = current == .lossless ? "flac" : "m4a"
            } else if song.source == .kugou {
                ext = current == .lossless ? "flac" : "mp3"
            } else {
                ext = current == .lossless ? "flac" : "mp3"
            }
            let dest = dir.appendingPathComponent("\(safeName).\(ext)")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
            } catch {
                lastError = NetEaseError.unknown("保存失败：\(error.localizedDescription)")
                continue
            }
            return .success(DownloadResult(url: dest, downgraded: index > 0))
        }
        return .failure(lastError)
    }

    private func resolveURL(song: Song, quality: DownloadQuality) async -> String? {
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
            kugouID: thirdPartyKugouID
        ) {
            BeansLogger.shared.log("下载使用第三方音源：\(song.name) 来源=\(resolved.source)", level: .info)
            return resolved.url.absoluteString
        }

        if UnblockSourceStore.singleSourceMode {
            return nil
        }

        if song.source == .qq, let mid = song.qqMid {
            return try? await QQMusicAPI.shared.songURL(songmid: mid, mediaMid: song.qqMediaMid, br: quality.qqBR)
        } else if song.source == .kugou {
            return try? await KugouMusicAPI.shared.songURL(song: song)
        } else {
            let urls = try? await NetEaseAPI.shared.songURLs(ids: [song.id], level: quality.neteaseLevel)
            return urls?[song.id]
        }
    }
}
