import SwiftUI

enum MediaShadowLevel {
    case control
    case subtle
    case regular
    case prominent

    var radius: CGFloat {
        switch self {
        case .control:
            return 8
        case .subtle:
            return 6
        case .regular:
            return 10
        case .prominent:
            return 14
        }
    }

    var yOffset: CGFloat {
        switch self {
        case .control:
            return 3
        case .subtle:
            return 2
        case .regular:
            return 4
        case .prominent:
            return 6
        }
    }

    func opacity(colorScheme: ColorScheme) -> Double {
        switch (self, colorScheme) {
        case (.control, .light):
            return 0.08
        case (.control, .dark):
            return 0.14
        case (.subtle, .light):
            return 0.08
        case (.regular, .light):
            return 0.11
        case (.prominent, .light):
            return 0.15
        case (.subtle, .dark):
            return 0.18
        case (.regular, .dark):
            return 0.24
        case (.prominent, .dark):
            return 0.30
        case (_, _):
            return 0.18
        }
    }
}

private struct MediaShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let level: MediaShadowLevel
    let opacityScale: Double

    func body(content: Content) -> some View {
        content
            .shadow(
                color: .black.opacity(level.opacity(colorScheme: colorScheme) * opacityScale),
                radius: level.radius,
                x: 0,
                y: level.yOffset
            )
    }
}

extension View {
    func mediaShadow(_ level: MediaShadowLevel = .regular) -> some View {
        modifier(MediaShadowModifier(level: level, opacityScale: 1))
    }

    func mediaShadow(_ level: MediaShadowLevel = .regular, opacityScale: Double) -> some View {
        modifier(MediaShadowModifier(level: level, opacityScale: opacityScale))
    }

    func videoCoverSurface(
        cornerRadius: CGFloat,
        shadowLevel: MediaShadowLevel? = nil,
        emphasizesBorder: Bool = false,
        shadowOpacityScale: Double = 1,
        borderOpacityScale: Double = 1,
        appliesUnifiedBorder: Bool = true
    ) -> some View {
        modifier(
            VideoCoverSurfaceModifier(
                cornerRadius: cornerRadius,
                shadowLevel: shadowLevel,
                emphasizesBorder: emphasizesBorder,
                shadowOpacityScale: shadowOpacityScale,
                borderOpacityScale: borderOpacityScale,
                appliesUnifiedBorder: appliesUnifiedBorder
            )
        )
    }

    func unifiedVideoCoverBorder<BorderShape: Shape>(
        in shape: BorderShape,
        opacityScale: Double = 1
    ) -> some View {
        modifier(
            UnifiedVideoCoverBorderModifier(
                shape: shape,
                opacityScale: opacityScale
            )
        )
    }
}

private struct VideoCoverSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let shadowLevel: MediaShadowLevel?
    let emphasizesBorder: Bool
    let shadowOpacityScale: Double
    let borderOpacityScale: Double
    let appliesUnifiedBorder: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let baseSurface = content
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(shape)

        if appliesUnifiedBorder {
            styledSurface(
                baseSurface.unifiedVideoCoverBorder(
                    in: shape,
                    opacityScale: borderOpacityScale
                )
            )
        } else {
            styledSurface(
                baseSurface
                    .overlay {
                        shape.strokeBorder(outerStrokeColor, lineWidth: emphasizesBorder ? 0.9 : 0.7)
                    }
                    .overlay {
                        shape
                            .inset(by: 1)
                            .strokeBorder(innerStrokeColor, lineWidth: 0.6)
                    }
            )
        }
    }

    @ViewBuilder
    private func styledSurface<Surface: View>(_ surface: Surface) -> some View {
        if let shadowLevel {
            surface.mediaShadow(shadowLevel, opacityScale: shadowOpacityScale)
        } else {
            surface
        }
    }

    private var outerStrokeColor: Color {
        let opacity = emphasizesBorder ? 1.18 : 1
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.18 * opacity * borderOpacityScale)
        default:
            return Color.black.opacity(0.10 * opacity * borderOpacityScale)
        }
    }

    private var innerStrokeColor: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.10 * borderOpacityScale)
        default:
            return Color.white.opacity(0.34 * borderOpacityScale)
        }
    }
}

private struct UnifiedVideoCoverBorderModifier<BorderShape: Shape>: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    let shape: BorderShape
    let opacityScale: Double

    func body(content: Content) -> some View {
        content.overlay {
            shape
                .stroke(systemSeparatorColor, lineWidth: opticalLineWidth)
                .padding(opticalLineWidth * 0.5)
        }
    }

    private var systemSeparatorColor: Color {
        Color(.separator).opacity(0.72 * normalizedOpacityScale)
    }

    private var normalizedOpacityScale: Double {
        min(max(opacityScale, 0), 1)
    }

    private var physicalPixel: CGFloat {
        1 / max(displayScale, 1)
    }

    private var opticalLineWidth: CGFloat {
        max(0.5, physicalPixel)
    }
}
