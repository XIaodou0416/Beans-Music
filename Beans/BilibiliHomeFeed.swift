import Foundation

struct BilibiliFeedVideo: Identifiable, Codable {
    let song: Song
    let ownerAvatarURL: URL?
    let playCount: Int
    let danmakuCount: Int
    var id: String { song.identityKey }

    static func countLabel(_ count: Int) -> String {
        if count >= 100_000_000 { return String(format: "%.1f亿", Double(count) / 100_000_000) }
        if count >= 10_000 { return String(format: "%.1f万", Double(count) / 10_000) }
        return String(max(0, count))
    }
}
