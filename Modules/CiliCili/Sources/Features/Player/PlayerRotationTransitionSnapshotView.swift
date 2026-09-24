import Foundation
import SwiftUI

struct PlayerRotationTransitionSnapshotView: View {
    let snapshot: PlaybackTransitionSnapshot?
    let fallbackCoverURL: URL?
    let constrainsToVideoAspect: Bool

    var body: some View {
        GeometryReader { proxy in
            let stageSize = snapshotStageSize(in: proxy.size)
            ZStack {
                snapshotContent
                    .frame(
                        width: stageSize.width,
                        height: stageSize.height
                    )
                    .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var snapshotContent: some View {
        if let image = snapshot?.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Color.clear
        }
    }

    private func snapshotStageSize(in containerSize: CGSize) -> CGSize {
        guard constrainsToVideoAspect,
              containerSize.width > 1,
              containerSize.height > 1
        else { return containerSize }

        let videoAspectRatio = CGFloat(16.0 / 9.0)
        let containerAspectRatio = containerSize.width / containerSize.height
        if containerAspectRatio > videoAspectRatio {
            let height = containerSize.height
            return CGSize(width: height * videoAspectRatio, height: height)
        } else {
            let width = containerSize.width
            return CGSize(width: width, height: width / videoAspectRatio)
        }
    }
}
