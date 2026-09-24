import Foundation
#if DEBUG
import OSLog
#endif

#if DEBUG
private let dynamicContentFilterLogger = Logger(subsystem: "cc.bili", category: "DynamicDiagnostics")
#endif

struct DynamicFeedContentFilter {
    let libraryStore: LibraryStore

    func displayable(_ items: [DynamicFeedItem]?) -> [DynamicFeedItem] {
        (items ?? []).filter { item in
            let isDisplayable = item.displayText?.isEmpty == false
                || item.archive != nil
                || item.live != nil
                || item.paidContent != nil
                || !item.imageItems.isEmpty
                || item.original?.hasDisplayableContent == true
#if DEBUG
            if !isDisplayable, item.author != nil {
                dynamicContentFilterLogger.debug("Dropped empty dynamic: \(item.contentDiagnosticSummary, privacy: .public)")
            }
#endif
            return isDisplayable
        }
    }

    func filtered(_ items: [DynamicFeedItem]) -> [DynamicFeedItem] {
        var filteredItems = items
        if libraryStore.blocksAdDynamics {
            filteredItems = filteredItems.filter { !$0.containsDynamicAdPromotion }
        }
        if libraryStore.blocksGoodsDynamics {
            filteredItems = filteredItems.filter { !$0.containsGoodsPromotion }
        }
        let blockedKeywords = libraryStore.blockedDynamicKeywords
        if !blockedKeywords.isEmpty {
            filteredItems = filteredItems.filter { !$0.matchesBlockedDynamicKeywords(blockedKeywords) }
        }
        return filteredItems
    }

    func uniqueAppendItems(
        _ more: [DynamicFeedItem],
        to items: [DynamicFeedItem]
    ) -> [DynamicFeedItem] {
        let existing = Set(items.map(\.id))
        return items + more.filter { !existing.contains($0.id) }
    }
}
