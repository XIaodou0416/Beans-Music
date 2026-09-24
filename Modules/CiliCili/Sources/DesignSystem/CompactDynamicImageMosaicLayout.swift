import SwiftUI

struct CompactDynamicImageMosaicRow: Identifiable {
    let id: Int
    let items: [CompactDynamicImageDisplayItem]
}

struct CompactDynamicImageMosaicLayout {
    let primaryTile: CompactDynamicImageDisplayItem?
    let topTiles: [CompactDynamicImageDisplayItem]
    let trailingTiles: [CompactDynamicImageDisplayItem]
    let bottomTiles: [CompactDynamicImageDisplayItem]
    let rows: [CompactDynamicImageMosaicRow]
    private let twoColumnRows: [CompactDynamicImageMosaicRow]
    private let threeColumnRows: [CompactDynamicImageMosaicRow]

    init(displayedImages: [CompactDynamicImageDisplayItem]) {
        primaryTile = displayedImages.first
        topTiles = Array(displayedImages.prefix(2))
        trailingTiles = Self.slice(displayedImages, from: 1, count: 2)
        bottomTiles = Self.bottomTiles(for: displayedImages)
        rows = Self.rowsForEightImageMosaic(displayedImages)
        twoColumnRows = Self.chunked(displayedImages, columns: 2)
        threeColumnRows = Self.chunked(displayedImages, columns: 3)
    }

    func rows(for columns: Int) -> [CompactDynamicImageMosaicRow] {
        columns == 2 ? twoColumnRows : threeColumnRows
    }

    private static func bottomTiles(for items: [CompactDynamicImageDisplayItem]) -> [CompactDynamicImageDisplayItem] {
        switch items.count {
        case 5:
            return slice(items, from: 2, count: 3)
        case 7:
            return slice(items, from: 3, count: 4)
        default:
            return []
        }
    }

    private static func rowsForEightImageMosaic(_ items: [CompactDynamicImageDisplayItem]) -> [CompactDynamicImageMosaicRow] {
        chunked(slice(items, from: 2, count: 6), columns: 3)
    }

    private static func slice(
        _ items: [CompactDynamicImageDisplayItem],
        from startIndex: Int,
        count: Int
    ) -> [CompactDynamicImageDisplayItem] {
        guard startIndex < items.count, count > 0 else { return [] }
        let endIndex = min(startIndex + count, items.count)
        return Array(items[startIndex..<endIndex])
    }

    private static func chunked(
        _ items: [CompactDynamicImageDisplayItem],
        columns: Int
    ) -> [CompactDynamicImageMosaicRow] {
        let columnCount = max(columns, 1)
        return stride(from: 0, to: items.count, by: columnCount).map { startIndex in
            CompactDynamicImageMosaicRow(
                id: startIndex / columnCount,
                items: Array(items[startIndex..<min(startIndex + columnCount, items.count)])
            )
        }
    }
}
