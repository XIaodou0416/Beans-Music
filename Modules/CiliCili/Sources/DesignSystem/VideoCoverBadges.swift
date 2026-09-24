import SwiftUI

enum VideoCoverBadgeShadow {
    static let storageKey = "cc.bili.display.videoCoverBadgeShadowOpacity.v1"
    static let defaultOpacity = 0.0
    static let opacityRange: ClosedRange<Double> = 0...1

    static func normalized(_ opacity: Double) -> Double {
        min(max(opacity, opacityRange.lowerBound), opacityRange.upperBound)
    }
}

enum VideoCoverBottomScrimSettings {
    static let storageKey = "cc.bili.display.videoCoverBottomScrimEnabled.v1"
    static let defaultIsEnabled = true
}

enum VideoCoverDurationBadgeSettings {
    static let storageKey = "cc.bili.display.videoCoverDurationBadgesEnabled.v1"
    static let defaultIsEnabled = false
}

private struct VideoCoverDurationBadgesVisibilityKey: EnvironmentKey {
    static let defaultValue = VideoCoverDurationBadgeSettings.defaultIsEnabled
}

extension EnvironmentValues {
    var showsVideoCoverDurationBadges: Bool {
        get { self[VideoCoverDurationBadgesVisibilityKey.self] }
        set { self[VideoCoverDurationBadgesVisibilityKey.self] = newValue }
    }
}

enum VideoCoverBadgeContrastBacking {
    static let storageKey = "cc.bili.display.videoCoverBadgeContrastBackingOpacity.v1"
    static let defaultOpacity = 0.35
    static let opacityRange: ClosedRange<Double> = 0...0.8

    static func normalized(_ opacity: Double) -> Double {
        min(max(opacity, opacityRange.lowerBound), opacityRange.upperBound)
    }
}

struct VideoCoverGlassBadge<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(.caption2.weight(.semibold))
            .videoCoverBadgeForeground(opacity: 0)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .videoCoverBadgeBackground(style: .regular, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 146, alignment: .leading)
            .clipped()
    }
}

struct VideoCoverDurationBadge: View {
    @Environment(\.showsVideoCoverDurationBadges) private var showsVideoCoverDurationBadges
    let duration: String
    private let maxWidth: CGFloat

    init(_ duration: String, maxWidth: CGFloat = 96) {
        self.duration = duration
        self.maxWidth = maxWidth
    }

    var body: some View {
        if showsVideoCoverDurationBadges {
            Text(duration)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .videoCoverBadgeForeground(opacity: 0)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.86)
                .allowsTightening(true)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .videoCoverBadgeBackground(style: .clear, in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: maxWidth, alignment: .trailing)
                .clipped()
                .accessibilityLabel("视频时长 \(duration)")
        }
    }
}

struct VideoCoverViewCountBadge: View {
    let viewText: String

    init(_ viewText: String) {
        self.viewText = viewText
    }

    var body: some View {
        Label(viewText, systemImage: "play.fill")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .videoCoverBadgeForeground(opacity: 0)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .videoCoverBadgeBackground(style: .regular, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 112, alignment: .leading)
            .clipped()
            .accessibilityLabel("观看次数 \(viewText)")
    }
}

struct VideoCoverPlayBadge: View {
    var size: CGFloat = 40
    var iconSize: CGFloat = 15

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: iconSize, weight: .bold))
                .videoCoverBadgeForeground(opacity: 0)
                .offset(x: 1)
                .frame(width: size, height: size)
                .videoCoverBadgeBackground(style: .clear, in: Circle())
                .videoCoverControlShadow()
                .accessibilityHidden(true)
        }
    }
}

struct VideoCoverBottomScrim: View {
    var opacity: Double = 0.30
    var heightFraction: CGFloat = 1.0 / 3.0

    var body: some View {
        EmptyView()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum VideoCoverBadgeGlassStyle {
    case clear
    case regular
}

private struct VideoCoverBadgeBackgroundModifier<BadgeShape: InsettableShape>: ViewModifier {
    let shape: BadgeShape
    let style: VideoCoverBadgeGlassStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .clear:
            content
                .videoCoverReadableBacking(style: style, in: shape)
                .biliPlayerClearGlass(interactive: false, in: shape)
        case .regular:
            content
                .videoCoverReadableBacking(style: style, in: shape)
                .biliRegularGlassEffect(in: shape)
        }
    }
}

extension View {
    func videoCoverBadgeBackground<S: InsettableShape>(
        style: VideoCoverBadgeGlassStyle,
        in shape: S
    ) -> some View {
        modifier(VideoCoverBadgeBackgroundModifier(shape: shape, style: style))
    }

    func videoCoverBadgeForeground(opacity: Double) -> some View {
        modifier(VideoCoverBadgeForegroundModifier(opacity: opacity))
    }

    func videoCoverBadgeForegroundShadow(opacity: Double) -> some View {
        self
    }

    func videoCoverReadableBacking<S: InsettableShape>(
        style: VideoCoverBadgeGlassStyle,
        in shape: S
    ) -> some View {
        modifier(VideoCoverReadableBackingModifier(shape: shape, style: style))
    }
}

private struct VideoCoverBadgeForegroundModifier: ViewModifier {
    let opacity: Double

    func body(content: Content) -> some View {
        content.biliLiquidGlassForeground(shadowOpacity: 0)
    }
}

private extension View {
    func videoCoverControlShadow() -> some View {
        self
    }
}

private struct VideoCoverReadableBackingModifier<BadgeShape: InsettableShape>: ViewModifier {
    @AppStorage(VideoCoverBadgeContrastBacking.storageKey) private var contrastOpacity = VideoCoverBadgeContrastBacking.defaultOpacity
    let shape: BadgeShape
    let style: VideoCoverBadgeGlassStyle

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(Color.black.opacity(backingOpacity))
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 0.5)
            }
    }

    private var backingOpacity: Double {
        let normalizedOpacity = VideoCoverBadgeContrastBacking.normalized(contrastOpacity)
        switch style {
        case .clear:
            return VideoCoverBadgeContrastBacking.normalized(normalizedOpacity + 0.05)
        case .regular:
            return VideoCoverBadgeContrastBacking.normalized(normalizedOpacity - 0.05)
        }
    }

    private var strokeOpacity: Double {
        switch style {
        case .clear:
            return 0.18
        case .regular:
            return 0.12
        }
    }
}
