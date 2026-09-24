import SwiftUI

struct CompactDynamicThreeImageMosaicLayout: View {
    let tileContext: CompactDynamicImageTileContext
    let layout: CompactDynamicImageMosaicLayout

    var body: some View {
        HStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
            if let first = layout.primaryTile {
                CompactDynamicImageTile(
                    context: tileContext,
                    item: first,
                    size: CGSize(
                        width: CompactDynamicImageMosaicMetrics.largeSide,
                        height: CompactDynamicImageMosaicMetrics.largeSide
                    )
                )
            }

            VStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                ForEach(layout.trailingTiles) { item in
                    CompactDynamicImageTile(
                        context: tileContext,
                        item: item,
                        size: CGSize(
                            width: CompactDynamicImageMosaicMetrics.smallSide,
                            height: CompactDynamicImageMosaicMetrics.smallSide
                        )
                    )
                }
            }
        }
        .frame(
            width: CompactDynamicImageMosaicMetrics.compactWidth,
            height: CompactDynamicImageMosaicMetrics.largeSide,
            alignment: .leading
        )
    }
}

struct CompactDynamicFiveImageMosaicLayout: View {
    let tileContext: CompactDynamicImageTileContext
    let layout: CompactDynamicImageMosaicLayout

    var body: some View {
        VStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
            HStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                ForEach(layout.topTiles) { item in
                    CompactDynamicImageTile(
                        context: tileContext,
                        item: item,
                        size: CGSize(
                            width: CompactDynamicImageMosaicMetrics.mediumSide,
                            height: CompactDynamicImageMosaicMetrics.mediumSide
                        )
                    )
                }
            }

            HStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                ForEach(layout.bottomTiles) { item in
                    CompactDynamicImageTile(
                        context: tileContext,
                        item: item,
                        size: CGSize(
                            width: CompactDynamicImageMosaicMetrics.smallSide,
                            height: CompactDynamicImageMosaicMetrics.smallSide
                        )
                    )
                }
            }
        }
        .frame(width: CompactDynamicImageMosaicMetrics.compactWidth, alignment: .topLeading)
    }
}

struct CompactDynamicSevenImageMosaicLayout: View {
    let tileContext: CompactDynamicImageTileContext
    let layout: CompactDynamicImageMosaicLayout

    var body: some View {
        VStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
            HStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                if let first = layout.primaryTile {
                    CompactDynamicImageTile(
                        context: tileContext,
                        item: first,
                        size: CGSize(
                            width: CompactDynamicImageMosaicMetrics.largeSide,
                            height: CompactDynamicImageMosaicMetrics.largeSide
                        )
                    )
                }

                VStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                    ForEach(layout.trailingTiles) { item in
                        CompactDynamicImageTile(
                            context: tileContext,
                            item: item,
                            size: CGSize(
                                width: CompactDynamicImageMosaicMetrics.smallSide,
                                height: CompactDynamicImageMosaicMetrics.smallSide
                            )
                        )
                    }
                }
            }

            HStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                ForEach(layout.bottomTiles) { item in
                    CompactDynamicImageTile(
                        context: tileContext,
                        item: item,
                        size: CGSize(
                            width: CompactDynamicImageMosaicMetrics.footerSide,
                            height: CompactDynamicImageMosaicMetrics.footerSide
                        )
                    )
                }
            }
        }
        .frame(width: CompactDynamicImageMosaicMetrics.compactWidth, alignment: .topLeading)
    }
}

struct CompactDynamicEightImageMosaicLayout: View {
    let tileContext: CompactDynamicImageTileContext
    let layout: CompactDynamicImageMosaicLayout

    var body: some View {
        VStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
            HStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                ForEach(layout.topTiles) { item in
                    CompactDynamicImageTile(
                        context: tileContext,
                        item: item,
                        size: CGSize(
                            width: CompactDynamicImageMosaicMetrics.mediumSide,
                            height: CompactDynamicImageMosaicMetrics.mediumSide
                        )
                    )
                }
            }

            CompactDynamicImageFixedRows(
                tileContext: tileContext,
                rows: layout.rows,
                side: CompactDynamicImageMosaicMetrics.smallSide
            )
        }
        .frame(width: CompactDynamicImageMosaicMetrics.compactWidth, alignment: .topLeading)
    }
}

private struct CompactDynamicImageFixedRows: View {
    let tileContext: CompactDynamicImageTileContext
    let rows: [CompactDynamicImageMosaicRow]
    let side: CGFloat

    var body: some View {
        VStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
            ForEach(rows) { row in
                HStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                    ForEach(row.items) { item in
                        CompactDynamicImageTile(
                            context: tileContext,
                            item: item,
                            size: CGSize(width: side, height: side)
                        )
                    }
                }
            }
        }
    }
}
