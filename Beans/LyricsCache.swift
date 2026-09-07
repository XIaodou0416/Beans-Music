import Foundation

/// Persists raw lyrics so a song can render immediately when it is played again.
final class LyricsCache {
    static let shared = LyricsCache()

    private struct Entry: Codable {
        let lyric: String
        let translation: String?
        let savedAt: Date
    }

    private let prefix = "beans.lyrics.cache.v1."
    private let maxAge: TimeInterval = 14 * 24 * 60 * 60

    private init() {}

    func value(for key: String) -> (lyric: String, translation: String?)? {
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        guard let data = UserDefaults.standard.data(forKey: prefix + safeKey),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              Date().timeIntervalSince(entry.savedAt) < maxAge,
              !entry.lyric.isEmpty else { return nil }
        return (entry.lyric, entry.translation)
    }

    func save(lyric: String, translation: String?, for key: String) {
        guard !lyric.isEmpty else { return }
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let entry = Entry(lyric: lyric, translation: translation, savedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: prefix + safeKey)
    }
}
