struct DynamicImageGridRow: Identifiable {
    let id: Int
    let items: [DynamicImageDisplayItem]
}

struct DynamicImageGridLayout {
    let primaryTile: DynamicImageDisplayItem?
    let topTiles: [DynamicImageDisplayItem]
    let trailingTiles: [DynamicImageDisplayItem]
    let middleTiles: [DynamicImageDisplayItem]
    let bottomTiles: [DynamicImageDisplayItem]
    let eightImageRows: [DynamicImageGridRow]
    private let twoColumnRows: [DynamicImageGridRow]
    private let threeColumnRows: [DynamicImageGridRow]

    init(displayedImages: [DynamicImageDisplayItem]) {
        primaryTile = displayedImages.first
        topTiles = Self.slice(displayedImages, from: 0, count: 2)
        trailingTiles = Self.slice(displayedImages, from: 1, count: 2)
        middleTiles = Self.slice(displayedImages, from: 2, count: 3)
        bottomTiles = Self.slice(displayedImages, from: 3, count: 4)
        eightImageRows = Self.chunked(Self.slice(displayedImages, from: 2, count: 6), columns: 3)
        twoColumnRows = Self.chunked(displayedImages, columns: 2)
        threeColumnRows = Self.chunked(displayedImages, columns: 3)
    }

    func rows(for columns: Int) -> [DynamicImageGridRow] {
        columns == 2 ? twoColumnRows : threeColumnRows
    }

    private static func slice(
        _ items: [DynamicImageDisplayItem],
        from startIndex: Int,
        count: Int
    ) -> [DynamicImageDisplayItem] {
        guard startIndex < items.count, count > 0 else { return [] }
        let endIndex = min(startIndex + count, items.count)
        return Array(items[startIndex..<endIndex])
    }

    private static func chunked(
        _ items: [DynamicImageDisplayItem],
        columns: Int
    ) -> [DynamicImageGridRow] {
        let columnCount = max(columns, 1)
        return stride(from: 0, to: items.count, by: columnCount).map { startIndex in
            DynamicImageGridRow(
                id: startIndex / columnCount,
                items: Array(items[startIndex..<min(startIndex + columnCount, items.count)])
            )
        }
    }
}
