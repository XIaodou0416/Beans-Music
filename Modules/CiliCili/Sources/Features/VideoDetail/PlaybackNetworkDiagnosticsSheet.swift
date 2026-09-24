import Foundation
import SwiftUI

struct PlaybackNetworkDiagnosticsSheet: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    @ObservedObject var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject var performanceObserver: PlayerPerformanceSessionObserver
    @State var sheetState = PlaybackNetworkDiagnosticsSheetState()

    init(
        diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore,
        relatedStore: VideoDetailRelatedRenderStore,
        libraryStore: LibraryStore
    ) {
        self.diagnosticsStore = diagnosticsStore
        self.relatedStore = relatedStore
        self.libraryStore = libraryStore
        _performanceObserver = StateObject(
            wrappedValue: PlayerPerformanceSessionObserver(
                metricsID: diagnosticsStore.metricsID,
                isAutoOptimizationEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
            )
        )
    }

    var runtimeContext: PlaybackNetworkDiagnosticsRuntimeContext {
        PlaybackNetworkDiagnosticsRuntimeContext(
            diagnosticsStore: diagnosticsStore,
            performanceObserver: performanceObserver,
            playbackURLPreferenceSnapshots: sheetState.playbackURLPreferenceSnapshots
        )
    }

    var body: some View {
        NavigationStack {
            PlaybackNetworkDiagnosticsSheetContent(
                diagnosticsStore: diagnosticsStore,
                relatedStore: relatedStore,
                libraryStore: libraryStore,
                formConfiguration: formConfiguration,
                lifecycleConfiguration: lifecycleConfiguration,
                dismiss: dismiss
            )
        }
        .onDisappear {
            cancelSheetTasks()
        }
        .onChange(of: diagnosticsStore.metricsID) { _, _ in
            cancelPlaybackCDNProbe()
        }
    }
}
