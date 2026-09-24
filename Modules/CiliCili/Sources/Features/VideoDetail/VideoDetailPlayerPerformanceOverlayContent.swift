import SwiftUI

struct PlayerPerformanceOverlayContent: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    let metricsID: String
    let session: PlayerPerformanceSession?
    let playerViewModel: PlayerStateViewModel?
    let experimentSnapshot: VideoDetailPerformanceExperimentSnapshot
    let panelWidth: CGFloat
    let maximumHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)

            PlayerPerformanceOverlayHeaderRow(
                metricsID: metricsID,
                copyTextProvider: copyText
            )

            Divider()
                .opacity(0.55)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 7) {
                    if let session {
                        PlayerPerformanceOverlayLoadedContent(
                            diagnosticsStore: diagnosticsStore,
                            session: session,
                            playerViewModel: playerViewModel,
                            experimentSnapshot: experimentSnapshot
                        )
                    } else {
                        PlayerPerformanceOverlayEmptyContent(
                            diagnosticsStore: diagnosticsStore,
                            playerViewModel: playerViewModel,
                            experimentSnapshot: experimentSnapshot
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: max(maximumHeight - 44, 160), alignment: .top)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: panelWidth, alignment: .topLeading)
        .frame(maxHeight: maximumHeight, alignment: .topLeading)
        .background(
            PlayerPerformanceOverlayFormatting.panelBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PlayerPerformanceOverlayFormatting.panelStroke, lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }

    private func copyText() -> String? {
        PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.text(
            metricsID: metricsID,
            session: session,
            diagnosticsStore: diagnosticsStore,
            playerViewModel: playerViewModel,
            experimentSnapshot: experimentSnapshot
        )
    }
}
