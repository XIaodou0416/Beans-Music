import Foundation

enum BiliPlayerPresentation: Equatable {
    case fullScreen
    case embedded
}

enum BiliPlaybackRate: Double, CaseIterable, Identifiable {
    case x075 = 0.75
    case x10 = 1.0
    case x125 = 1.25
    case x15 = 1.5
    case x20 = 2.0

    var id: Double { rawValue }

    var title: String {
        rawValue == 1.0 ? "1.0x" : "\(rawValue.formatted(.number.precision(.fractionLength(0...2))))x"
    }
}
