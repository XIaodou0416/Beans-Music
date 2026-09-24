import SwiftUI

struct VideoDetailNetworkDiagnosticsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("网络诊断", systemImage: "waveform.path.ecg.rectangle")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityLabel("打开网络诊断")
    }
}
