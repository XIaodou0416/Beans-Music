import Foundation

extension VideoDetailViewModel {
    func seekWarmupVariantLimit(pressureReason: String?) -> Int {
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return 1 }
        switch environment.networkClass {
        case .wifi:
            return pressureReason == nil ? 2 : 3
        case .unknown:
            return pressureReason == nil ? 1 : 2
        case .cellular, .constrained:
            return 1
        }
    }

    func seekWarmupPressureReason(primary variant: PlayVariant) -> String? {
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return nil }
        let profile = playbackAdaptationProfile
        guard profile.isEnabled else { return nil }

        if let session = PlayerPerformanceStore.shared.session(for: detail.bvid) {
            if (session.accessLogStallCount ?? 0) > 0 {
                return "accesslog-stall"
            }
            if session.seekRecoverySlowCount > 0
                || session.lastSeekRecoveryMilliseconds.map({ $0 >= 1_250 }) == true {
                return "seek-recovery"
            }
            if session.bufferCount > 0 {
                return "buffering"
            }
            if let observedKbps = session.observedBitrateKilobitsPerSecond,
               observedKbps > 0,
               let bandwidth = variant.bandwidth,
               bandwidth > 0 {
                let requiredKbps = max(Int((Double(bandwidth) / 1_000) * 1.15), 1)
                if observedKbps < requiredKbps {
                    return "low-throughput"
                }
            }
        }

        switch profile.level {
        case .normal, .fallback:
            return nil
        case .cautious:
            return "history-cautious"
        case .slow:
            return "history-slow"
        }
    }
}
