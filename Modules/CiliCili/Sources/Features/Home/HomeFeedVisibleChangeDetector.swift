import Foundation

nonisolated enum HomeFeedVisibleChangeDetector {
    static func hasVisibleChange(in page: [VideoItem], comparedTo previousIDs: [String]) -> Bool {
        guard !page.isEmpty else { return false }
        guard !previousIDs.isEmpty else { return true }
        let newFront = page.prefix(8).map(\.id)
        let oldFront = Array(previousIDs.prefix(8))
        return newFront != oldFront
    }
}
