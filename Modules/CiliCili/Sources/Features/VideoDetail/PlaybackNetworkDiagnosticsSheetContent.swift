import SwiftUI

struct PlaybackNetworkDiagnosticsSheetContent: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    @ObservedObject var libraryStore: LibraryStore
    let formConfiguration: PlaybackNetworkDiagnosticsFormConfiguration
    let lifecycleConfiguration: PlaybackNetworkDiagnosticsLifecycleConfiguration
    let dismiss: DismissAction

    var body: some View {
        PlaybackNetworkDiagnosticsFormContent(
            diagnosticsStore: diagnosticsStore,
            relatedStore: relatedStore,
            libraryStore: libraryStore,
            configuration: formConfiguration
        )
        .navigationTitle("网络诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            VideoDetailDoneToolbar(finish: dismissDiagnostics)
        }
        .playbackNetworkDiagnosticsLifecycle(configuration: lifecycleConfiguration)
    }

    private func dismissDiagnostics() {
        dismiss()
    }
}
