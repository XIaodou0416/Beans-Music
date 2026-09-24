import SwiftUI

struct PlaybackNetworkHLSBridgeSection: View {
    let variant: PlayVariant?
    let snapshots: [HLSBridgeSourceDiagnosticsSnapshot]

    var body: some View {
        if variant?.audioURL != nil {
            Section("HLSBridge") {
                if snapshots.isEmpty {
                    Text("等待 HLSBridge 线路样本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshots.prefix(8)) { snapshot in
                        PlaybackNetworkHLSBridgeSourceRow(snapshot: snapshot)
                    }
                }
            }
        }
    }
}
