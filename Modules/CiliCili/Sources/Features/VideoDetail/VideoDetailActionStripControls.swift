import SwiftUI

struct VideoDetailActionStripShareButton: View {
    let shareURL: URL?
    let shareSubject: String
    let shareMessage: String
    let onShareTap: () -> Void

    var body: some View {
        if let shareURL {
            ShareLink(
                item: shareURL,
                subject: Text(shareSubject),
                message: Text(shareMessage)
            ) {
                VideoDetailActionStripIconLabel(
                    systemImage: "square.and.arrow.up",
                    foregroundStyle: .primary
                )
            }
            .buttonBorderShape(.circle)
            .controlSize(.mini)
            .biliGlassButtonStyle()
            .contentShape(Circle())
            .simultaneousGesture(TapGesture().onEnded { _ in onShareTap() })
            .accessibilityLabel("分享视频")
        } else {
            VideoDetailActionStripIconButton(
                accessibilityTitle: "分享视频",
                systemImage: "square.and.arrow.up",
                foregroundStyle: .secondary,
                isDisabled: true,
                action: {}
            )
        }
    }
}
