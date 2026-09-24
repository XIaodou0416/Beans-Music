import SwiftUI

struct PlaybackNetworkCDNHostRows: View {
    let variant: PlayVariant?

    var body: some View {
        PlaybackNetworkDiagnosticRow(
            title: "视频 Host",
            value: variant?.videoURL?.host ?? "未获取"
        )

        if let audioURL = variant?.audioURL {
            PlaybackNetworkDiagnosticRow(title: "音频 Host", value: audioURL.host ?? "未知")
        }
    }
}
