import SwiftUI

struct DynamicLiveCover: View {
    let live: DynamicLive
    let showsCenterBadge: Bool

    var body: some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack(alignment: .topLeading) {
                Color.clear

                let sourceURLString = live.normalizedCoverURL
                CachedRemoteImage(
                    url: sourceURLString.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 420, height: 236)) },
                    fallbackURL: sourceURLString.flatMap(URL.init(string:)),
                    targetPixelSize: 420,
                    animatesAppearance: false
                ) { image in
                    image.resizable().scaledToFill()
                } phasePlaceholder: { phase, _ in
                    BiliMediaPlaceholder(
                        style: .video,
                        phase: phase,
                        iconSize: 17
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if showsCenterBadge {
                    Label("直播中", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .videoCoverBadgeBackground(style: .regular, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Text(live.statusText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .videoCoverBadgeBackground(style: .regular, in: Capsule())
                    .padding(8)
            }
        }
        .background(BiliMediaPlaceholder(style: .video, iconSize: 17))
        .videoCoverSurface(cornerRadius: 12, shadowLevel: .regular)
    }
}

struct DynamicLiveTitle: View {
    let live: DynamicLive
    let style: DynamicLivePreview.Style

    var body: some View {
        Text(live.displayTitle)
            .appTypography(
                style == .large ? .feedVideoTitle : .compactVideoTitle,
                fallback: style == .large ? .system(size: 16, weight: .semibold) : .subheadline.weight(.semibold)
            )
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DynamicLiveMetadata: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let live: DynamicLive

    var body: some View {
        HStack(spacing: 10) {
            Label(live.statusText, systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(appTintColor)

            if let viewerText = live.viewerText {
                Text(viewerText)
            }

            if let areaName = live.areaName, !areaName.isEmpty {
                Text(areaName)
                    .lineLimit(1)
            }
        }
        .appTypography(.metadata, fallback: .system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
