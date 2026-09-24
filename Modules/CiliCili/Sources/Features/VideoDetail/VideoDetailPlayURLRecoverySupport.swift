import Foundation

extension VideoDetailViewModel {
    var playURLRecoveryTimeoutNanoseconds: UInt64 {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? 6_500_000_000
            : 6_000_000_000
    }

    var playURLFullRecoveryTimeoutNanoseconds: UInt64 {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? 10_000_000_000
            : 8_500_000_000
    }

    func isPlayURLRateLimited(_ error: Error) -> Bool {
        if case BiliAPIError.api(let code, _) = error, code == -351 {
            return true
        }
        return false
    }
}
