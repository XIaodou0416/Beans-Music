import Foundation

nonisolated enum HomeFeedImagePrefetchPolicy {
    static func initialPrefetchLimit(layout: HomeFeedLayout, isConservative: Bool) -> Int {
        guard !isConservative else { return 3 }
        return usesDoubleColumn(layout) ? 6 : 5
    }

    static func maximumConcurrentLoads(isConservative: Bool) -> Int {
        isConservative ? 1 : 2
    }

    static func initialPrewarmDeadlineNanoseconds(isConservative: Bool) -> UInt64 {
        isConservative ? 260_000_000 : 380_000_000
    }

    static func lookaheadStartIndex(visibleIndex: Int, layout: HomeFeedLayout) -> Int {
        let lead = usesDoubleColumn(layout) ? 4 : 3
        return max(0, visibleIndex + lead)
    }

    static func lookaheadLimit(layout: HomeFeedLayout, isConservative: Bool) -> Int {
        guard !isConservative else { return 3 }
        return usesDoubleColumn(layout) ? 6 : 5
    }

    static func lookaheadDebounceNanoseconds() -> UInt64 {
        100_000_000
    }

    private static func usesDoubleColumn(_ layout: HomeFeedLayout) -> Bool {
        switch layout {
        case .doubleColumn, .borderedDoubleColumn:
            true
        case .singleColumn, .borderedSingleColumn:
            false
        }
    }
}
