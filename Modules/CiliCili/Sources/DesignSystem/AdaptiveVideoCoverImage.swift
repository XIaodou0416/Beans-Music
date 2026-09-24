import SwiftUI

struct AdaptiveVideoCoverImage: View {
    enum Style {
        case exactCrop
        case maxSide
    }

    let display: VideoCardDisplayModel
    let style: Style
    var fixedSize: CGSize?
    var maximumPixelLength: Int = 1280
    var onPhaseChange: ((RemoteImageLoadingPhase) -> Void)?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let fixedSize {
            remoteImage(fitting: fixedSize)
                .frame(width: fixedSize.width, height: fixedSize.height)
                .clipped()
        } else {
            GeometryReader { proxy in
                if proxy.size.width > 1, proxy.size.height > 1 {
                    remoteImage(fitting: proxy.size)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    BiliMediaPlaceholder(style: .video, iconSize: 18)
                }
            }
        }
    }

    @ViewBuilder
    private func remoteImage(fitting size: CGSize) -> some View {
        CachedRemoteImage(
            url: thumbnailURL(fitting: size),
            fallbackURL: fallbackURL(fitting: size),
            targetPixelSize: display.coverTargetPixelSize(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            ),
            animatesAppearance: false
        ) { image in
            image
                .resizable()
                .scaledToFill()
                .onAppear {
                    onPhaseChange?(.loaded)
                }
        } phasePlaceholder: { phase, _ in
            BiliMediaPlaceholder(
                style: .video,
                phase: phase,
                showsSpinner: phase == .loading,
                iconSize: 18
            )
            .onAppear {
                onPhaseChange?(phase)
            }
            .onChange(of: phase) { _, newPhase in
                onPhaseChange?(newPhase)
            }
        }
    }

    private func thumbnailURL(fitting size: CGSize) -> URL? {
        switch style {
        case .exactCrop:
            return display.coverThumbnailURL(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            )
        case .maxSide:
            return display.largeThumbnailURL(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            )
        }
    }

    private func fallbackURL(fitting size: CGSize) -> URL? {
        switch style {
        case .exactCrop:
            return display.sourceCoverURL ?? display.largeThumbnailURL(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            )
        case .maxSide:
            return display.sourceCoverURL
        }
    }
}
