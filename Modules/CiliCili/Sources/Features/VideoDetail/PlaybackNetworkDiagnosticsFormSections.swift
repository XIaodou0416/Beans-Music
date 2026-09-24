import SwiftUI

struct PlaybackNetworkDiagnosticsFormSections: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    @ObservedObject var libraryStore: LibraryStore

    let configuration: PlaybackNetworkDiagnosticsFormConfiguration

    var body: some View {
        PlaybackNetworkDiagnosticsFormSectionBuilder(
            diagnosticsStore: diagnosticsStore,
            relatedStore: relatedStore,
            libraryStore: libraryStore,
            configuration: configuration,
            runtimeContext: configuration.runtimeContext
        ).sections
    }
}
