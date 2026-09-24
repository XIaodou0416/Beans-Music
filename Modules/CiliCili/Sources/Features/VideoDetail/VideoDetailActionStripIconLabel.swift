import SwiftUI

struct VideoDetailActionStripIconLabel: View {
    let systemImage: String
    let foregroundStyle: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: VideoDetailActionStrip.Metrics.iconSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .frame(
                width: VideoDetailActionStrip.Metrics.actionLabelSide,
                height: VideoDetailActionStrip.Metrics.actionLabelSide
            )
            .foregroundStyle(foregroundStyle)
            .contentShape(Circle())
    }
}
