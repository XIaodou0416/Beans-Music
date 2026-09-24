import SwiftUI

@MainActor
struct VideoDetailNetworkDiagnosticsSheetHost: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        PlaybackNetworkDiagnosticsSheet(
            diagnosticsStore: viewModel.networkDiagnosticsRenderStore,
            relatedStore: viewModel.relatedRenderStore,
            libraryStore: libraryStore
        )
    }
}
