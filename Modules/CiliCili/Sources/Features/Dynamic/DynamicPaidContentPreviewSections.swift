import SwiftUI

struct DynamicPaidContentCover: View {
    let content: DynamicPaidContent
    let style: DynamicPaidContentPreview.Style

    var body: some View {
        FixedAspectPreview(aspectRatio: 16 / 9) {
            ZStack {
                BiliMediaPlaceholder(style: .video, iconSize: 17)

                if let coverURLString = content.normalizedCoverURL {
                    CachedRemoteImage(
                        url: URL(string: coverURLString.biliCoverThumbnailURL(width: 640, height: 360)),
                        fallbackURL: URL(string: coverURLString),
                        targetPixelSize: 640,
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
                }

                VideoCoverBottomScrim()

                if content.kind == .video {
                    DynamicVideoPlayBadge(size: style == .large ? 34 : 28, iconSize: style == .large ? 14 : 12)
                        .padding(style == .large ? 8 : 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                DynamicPaidContentBadge(content: content)
                    .padding(style == .large ? 10 : 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .videoCoverSurface(
            cornerRadius: style == .large ? 16 : 10,
            shadowLevel: style == .large ? .control : .regular
        )
    }
}

struct DynamicPaidContentTitle: View {
    let content: DynamicPaidContent
    let style: DynamicPaidContentPreview.Style

    var body: some View {
        Text(content.title)
            .appTypography(.feedVideoTitle)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DynamicPaidContentMetadata: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let content: DynamicPaidContent

    var body: some View {
        HStack(spacing: 8) {
            Label(kindText, systemImage: kindIcon)
                .foregroundStyle(content.isChargeExclusive ? appTintColor : .secondary)

            if let subtitle = content.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .lineLimit(1)
            }

            if content.isLocked {
                Label("需解锁", systemImage: "lock.fill")
                    .foregroundStyle(appTintColor)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var kindText: String {
        switch content.kind {
        case .video:
            return "视频"
        case .article:
            return "专栏"
        case .course:
            return "课程"
        case .collection:
            return "合集"
        case .unknown:
            return "内容"
        }
    }

    private var kindIcon: String {
        switch content.kind {
        case .video:
            return "play.rectangle.fill"
        case .article:
            return "doc.text.fill"
        case .course:
            return "graduationcap.fill"
        case .collection:
            return "rectangle.stack.fill"
        case .unknown:
            return "sparkles"
        }
    }
}

struct DynamicPaidContentBadge: View {
    let content: DynamicPaidContent

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Label(content.badgeText, systemImage: content.isChargeExclusive ? "bolt.fill" : "sparkles")
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .videoCoverBadgeForeground(opacity: 0)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .videoCoverBadgeBackground(style: .clear, in: Capsule())
        }
    }
}
