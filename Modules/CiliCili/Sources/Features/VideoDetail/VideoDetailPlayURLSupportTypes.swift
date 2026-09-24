import Foundation

enum VideoDetailPlayURLLoadMode {
    case normal
    case playbackRecovery

    var startMessage: String {
        switch self {
        case .normal:
            return "start"
        case .playbackRecovery:
            return "start recovery"
        }
    }

    var allowsStartupCache: Bool {
        switch self {
        case .normal:
            return true
        case .playbackRecovery:
            return false
        }
    }

    var allowsNetworkFailureCacheFallback: Bool {
        switch self {
        case .normal:
            return true
        case .playbackRecovery:
            return false
        }
    }
}

typealias VideoDetailPlayURLFallback = (data: PlayURLData, source: String)
