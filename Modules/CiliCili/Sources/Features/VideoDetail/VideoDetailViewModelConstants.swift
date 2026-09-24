import Foundation

extension VideoDetailViewModel {
    static let danmakuSegmentDuration: TimeInterval = 6 * 60
    static let relatedRecommendationsLimit = 5
    static let minimumExpandedRelatedCount = relatedRecommendationsLimit
    static let seekWarmupBucketDuration: TimeInterval = 30
    static let maxInFlightSeekWarmups = 1
    static let recentSeekWarmupLimit = 10
    static let qualitySwitchWarmupTimeout: TimeInterval = 1.15
    static let hlsRenditionPrebuildDelayNanoseconds: UInt64 = 850_000_000
    static let hlsRenditionPrebuildStepNanoseconds: UInt64 = 360_000_000
    static let hlsRenditionPrebuildTimeout: TimeInterval = 0.78
    static let playbackTransitionReleaseDelayNanoseconds: UInt64 = 220_000_000
    static let playbackTransitionFadeDurationNanoseconds: UInt64 = 280_000_000
    static let playbackTransitionMaximumRetainNanoseconds: UInt64 = 6_000_000_000
    static let playbackRecoveryReloadAttemptLimit = 2
    static let fullscreenTransitionMaskHoldNanoseconds: UInt64 = 160_000_000
    static let fullscreenTransitionMaskFadeDurationNanoseconds: UInt64 = 300_000_000
    static let fullscreenExitTransitionMaskHoldNanoseconds: UInt64 = 160_000_000
    static let fullscreenExitTransitionMaskFadeDurationNanoseconds: UInt64 = 360_000_000
    static let renderStoreSyncCoalescingDelayNanoseconds: UInt64 = 16_000_000
}
