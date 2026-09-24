import Foundation

extension HomeFeedSnapshotCache {
    static func snapshotURL(
        mode: HomeFeedMode,
        guestModeEnabled: Bool,
        recommendSource: HomeRecommendFeedSourcePreference,
        accountIdentityKey: String
    ) -> URL {
        let source = mode == .recommend ? recommendSource.rawValue : "default"
        let identity = mode == .recommend ? safePathComponent(accountIdentityKey) : "default"
        return directoryURL.appending(
            path: "\(mode.rawValue)-source-\(source)-guest-\(guestModeEnabled ? "1" : "0")-identity-\(identity).json"
        )
    }

    static func legacyKey(mode: HomeFeedMode, guestModeEnabled: Bool) -> String {
        "cc.bili.home.snapshot.\(mode.rawValue).guest-\(guestModeEnabled ? "1" : "0")"
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return result.isEmpty ? "default" : result
    }
}
