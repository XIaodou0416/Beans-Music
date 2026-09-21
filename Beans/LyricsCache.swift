import Foundation

/// Persists raw lyrics so a song can render immediately when it is played again.
final class LyricsCache {
    static let shared = LyricsCache()

    private struct Entry: Codable {
        let lyric: String
        let translation: String?
        let wordTiming: String?
        let wordFormat: String?
        let savedAt: Date

        init(lyric: String, translation: String?, wordTiming: String?, wordFormat: String?, savedAt: Date) {
            self.lyric = lyric
            self.translation = translation
            self.wordTiming = wordTiming
            self.wordFormat = wordFormat
            self.savedAt = savedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            lyric = try container.decode(String.self, forKey: .lyric)
            translation = try container.decodeIfPresent(String.self, forKey: .translation)
            wordTiming = try container.decodeIfPresent(String.self, forKey: .wordTiming)
            wordFormat = try container.decodeIfPresent(String.self, forKey: .wordFormat)
            savedAt = try container.decode(Date.self, forKey: .savedAt)
        }
    }

    private let prefix = "beans.lyrics.cache.v1."
    private let maxAge: TimeInterval = 14 * 24 * 60 * 60

    private init() {}

    func value(for key: String) -> (lyric: String, translation: String?, wordTiming: String?, wordFormat: LyricWordFormat?)? {
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        guard let data = UserDefaults.standard.data(forKey: prefix + safeKey),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              Date().timeIntervalSince(entry.savedAt) < maxAge,
              !entry.lyric.isEmpty else { return nil }
        return (entry.lyric, entry.translation, entry.wordTiming, entry.wordFormat.flatMap(LyricWordFormat.init(rawValue:)))
    }

    func save(lyric: String, translation: String?, wordTiming: String? = nil, wordFormat: LyricWordFormat? = nil, for key: String) {
        guard !lyric.isEmpty else { return }
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let entry = Entry(lyric: lyric, translation: translation, wordTiming: wordTiming, wordFormat: wordFormat?.rawValue, savedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: prefix + safeKey)
    }

    func clearAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
