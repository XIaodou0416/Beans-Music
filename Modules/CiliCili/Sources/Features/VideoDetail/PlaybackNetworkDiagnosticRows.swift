import SwiftUI

struct PlaybackNetworkDiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }
}
