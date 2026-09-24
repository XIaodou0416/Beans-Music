import Foundation

struct VideoDetailSponsorBlockState {
    var task: Task<Void, Never>?
    var segments: [SponsorBlockSegment] = []
    var identity: String?
    var generation = 0
}

extension VideoDetailViewModel {
    var sponsorBlockTask: Task<Void, Never>? {
        get { sponsorBlockState.task }
        set { sponsorBlockState.task = newValue }
    }

    var sponsorBlockSegments: [SponsorBlockSegment] {
        get { sponsorBlockState.segments }
        set { sponsorBlockState.segments = newValue }
    }

    var sponsorBlockIdentity: String? {
        get { sponsorBlockState.identity }
        set { sponsorBlockState.identity = newValue }
    }

    var sponsorBlockGeneration: Int {
        get { sponsorBlockState.generation }
        set { sponsorBlockState.generation = newValue }
    }
}
