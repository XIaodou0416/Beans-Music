import Foundation

enum CiliCiliPlaybackExperience: String, CaseIterable, Identifiable {
    case listen
    case watch = "video"

    static let storageKey = "beans.bilibili.experience"
    static let defaultRawValue = CiliCiliPlaybackExperience.listen.rawValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listen:
            return "听视频"
        case .watch:
            return "看视频"
        }
    }

    var playerContentMode: PlayerPlaybackContentMode {
        self == .listen ? .audioOnly : .video
    }

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? defaultRawValue) ?? .listen
    }
}
