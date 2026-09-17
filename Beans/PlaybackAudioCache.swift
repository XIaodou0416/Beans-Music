import Foundation
import Network

/// Keeps a bounded local copy of successfully played audio so a previously heard track can
/// start without resolving a fresh streaming URL when the device is offline.
final class PlaybackAudioCache {
    static let shared = PlaybackAudioCache()

    private struct Entry: Codable, Equatable {
        let filename: String
        var lastAccessed: Date
        let byteCount: Int64
    }

    private let defaultsKey = "beans.playbackAudioCache.v1"
    private let maximumBytes: Int64 = 10 * 1024 * 1024 * 1024
    private let directory: URL
    private let lock = NSLock()
    private var entries: [String: Entry]
    private var inFlight: Set<String> = []

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansPlaybackAudioCache", isDirectory: true)
        entries = Self.loadEntries(for: defaultsKey)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeMissingEntries()
    }

    func cachedURL(for song: Song) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[song.identityKey] else { return nil }
        let url = directory.appendingPathComponent(entry.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            entries.removeValue(forKey: song.identityKey)
            persistLocked()
            return nil
        }
        entry.lastAccessed = Date()
        entries[song.identityKey] = entry
        persistLocked()
        return url
    }

    func cache(song: Song, sourceURL: URL, headers: [String: String]) async {
        guard sourceURL.isFileURL == false else { return }
        guard beginCaching(song.identityKey) else { return }
        defer { finishCaching(song.identityKey) }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 300
        request.allHTTPHeaderFields = headers
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard Self.isUsableAudioFile(at: temporaryURL, response: response) else {
                try? FileManager.default.removeItem(at: temporaryURL)
                return
            }
            let ext = Self.audioExtension(for: temporaryURL, response: response, sourceURL: sourceURL)
            let filename = Self.filename(for: song.identityKey, ext: ext)
            let destination = directory.appendingPathComponent(filename)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            guard byteCount > 1024 else {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            store(songKey: song.identityKey, filename: filename, byteCount: byteCount)
        } catch {
            // Offline caching is best-effort and must never interrupt active streaming playback.
        }
    }

    private func beginCaching(_ songKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard entries[songKey] == nil, !inFlight.contains(songKey) else { return false }
        inFlight.insert(songKey)
        return true
    }

    private func finishCaching(_ songKey: String) {
        lock.lock()
        inFlight.remove(songKey)
        lock.unlock()
    }

    private func store(songKey: String, filename: String, byteCount: Int64) {
        lock.lock()
        defer { lock.unlock() }
        if let previous = entries[songKey], previous.filename != filename {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(previous.filename))
        }
        entries[songKey] = Entry(filename: filename, lastAccessed: Date(), byteCount: byteCount)
        evictLeastRecentlyUsedLocked()
        persistLocked()
    }

    private func removeMissingEntries() {
        lock.lock()
        defer { lock.unlock() }
        let retained = entries.filter { _, entry in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.filename).path)
        }
        guard retained != entries else { return }
        entries = retained
        persistLocked()
    }

    private func evictLeastRecentlyUsedLocked() {
        var total = entries.values.reduce(Int64(0)) { $0 + $1.byteCount }
        guard total > maximumBytes else { return }
        for (songKey, entry) in entries.sorted(by: { $0.value.lastAccessed < $1.value.lastAccessed }) {
            guard total > maximumBytes else { break }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.filename))
            entries.removeValue(forKey: songKey)
            total -= entry.byteCount
        }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func loadEntries(for key: String) -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func filename(for songKey: String, ext: String) -> String {
        let safeKey = songKey.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return safeKey + "-" + UUID().uuidString.lowercased() + "." + ext
    }

    private static func audioExtension(for fileURL: URL, response: URLResponse, sourceURL: URL) -> String {
        if let handle = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? handle.close() }
            let header = (try? handle.read(upToCount: 16)) ?? Data()
            if header.starts(with: Data("fLaC".utf8)) { return "flac" }
            if header.starts(with: Data("ID3".utf8)) { return "mp3" }
            if header.starts(with: Data("OggS".utf8)) { return "ogg" }
            if header.count >= 12,
               header[0] == 0x52, header[1] == 0x49, header[2] == 0x46, header[3] == 0x46,
               header[8] == 0x57, header[9] == 0x41, header[10] == 0x56, header[11] == 0x45 {
                return "wav"
            }
            if header.count >= 8,
               header[4] == 0x66, header[5] == 0x74, header[6] == 0x79, header[7] == 0x70 {
                return "m4a"
            }
            if header.count >= 2, header[0] == 0xFF, (header[1] & 0xF6) == 0xF0 { return "aac" }
        }
        let mime = response.mimeType?.lowercased() ?? ""
        if mime.contains("flac") { return "flac" }
        if mime.contains("mpeg") || mime.contains("mp3") { return "mp3" }
        if mime.contains("mp4") || mime.contains("m4a") { return "m4a" }
        if mime.contains("aac") { return "aac" }
        if mime.contains("ogg") { return "ogg" }
        let ext = sourceURL.pathExtension.lowercased()
        return ["mp3", "m4a", "flac", "aac", "ogg", "wav"].contains(ext) ? ext : "m4a"
    }

    private static func isUsableAudioFile(at url: URL, response: URLResponse) -> Bool {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return false }
        if let mime = response.mimeType?.lowercased(),
           mime.contains("text/") || mime.contains("json") || mime.contains("html") {
            return false
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 1024 else {
            return false
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 64)) ?? Data()
        let text = String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return !text.hasPrefix("{") && !text.hasPrefix("[")
            && !text.hasPrefix("<html") && !text.hasPrefix("<!doctype")
    }
}

final class BeansNetworkStatus {
    static let shared = BeansNetworkStatus()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var reachable = true

    var isReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachable
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.reachable = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "Beans.NetworkStatus"))
    }
}
