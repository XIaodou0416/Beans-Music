import Foundation

enum PlayerHorizontalSeekSensitivity {
    private static let piliPlusDefaultSecondsPerFullWidth: TimeInterval = 90

    static func secondsPerFullWidth(duration _: TimeInterval?) -> TimeInterval {
        piliPlusDefaultSecondsPerFullWidth
    }
}
