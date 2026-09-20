import SwiftUI

/// Lightweight Metal adaptation of the animated loop used for the launch surface.
/// The iOS 15 fallback keeps the launch transition useful on older systems.
struct BeansAnimatedLoop: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            BeansMetalAnimatedLoop()
        } else {
            BeansFallbackAnimatedLoop()
        }
    }
}

@available(iOS 17.0, *)
private struct BeansMetalAnimatedLoop: View {
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { context in
            let elapsed = Float(context.date.timeIntervalSince(start))
            Color.black
                .colorEffect(
                    Shader(
                        function: ShaderFunction(library: .default, name: "beansAnimatedLoop"),
                        arguments: [
                            .boundingRect,
                            .float(elapsed),
                            .float(0.052),
                            .float(0.00165),
                            .float(6),
                            .float(4.8),
                            .float(0.012),
                            .float(0.2),
                            .float(0.0),
                            .float(1.0),
                            .float2(0.0, 0.0),
                            .float(0),
                            .float(0),
                            .color(Color(red: 1.0, green: 0.13, blue: 0.31)),
                            .color(Color(red: 0.16, green: 1.0, blue: 0.86)),
                            .color(Color(red: 1.0, green: 0.76, blue: 0.28)),
                            .color(Color(red: 0.002, green: 0.004, blue: 0.005))
                        ]
                    )
                )
        }
        .drawingGroup(opaque: true, colorMode: .linear)
    }
}

private struct BeansFallbackAnimatedLoop: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black
            Circle()
                .stroke(Color.beansHighlight.opacity(0.45), lineWidth: 2)
                .frame(width: 110, height: 110)
                .scaleEffect(isAnimating ? 2.1 : 0.72)
                .opacity(isAnimating ? 0 : 0.9)
            Circle()
                .stroke(Color.beansAmber.opacity(0.34), lineWidth: 1.5)
                .frame(width: 78, height: 78)
                .scaleEffect(isAnimating ? 1.55 : 0.68)
                .opacity(isAnimating ? 0 : 0.72)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

struct BeansIntroAnimation: View {
    @State private var startedAt = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let entryProgress = Self.easeOutCubic(min(max(elapsed / 0.78, 0), 1))

            BeansAnimatedLoop()
                .opacity(0.92)
                .overlay {
                    VStack(spacing: 13) {
                        ZStack {
                            Image(systemName: "sparkle")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundStyle(Color(red: 0.99, green: 0.93, blue: 0.75))
                                .shadow(color: Color(red: 1.0, green: 0.76, blue: 0.28).opacity(0.42), radius: 18)
                            Image(systemName: "sparkle")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundStyle(.white.opacity(0.18))
                                .offset(x: -1, y: -1)
                        }
                        .scaleEffect(0.72 + entryProgress * 0.28)

                        Text("Beans Music")
                            .font(BeansFont.appFont(28, .semibold))
                            .foregroundStyle(Color(red: 0.973, green: 0.973, blue: 0.949))
                            .shadow(color: Color(red: 1.0, green: 0.13, blue: 0.31).opacity(0.20), radius: 12, x: -2)
                            .shadow(color: Color(red: 0.16, green: 1.0, blue: 0.86).opacity(0.16), radius: 12, x: 2)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color(red: 0.16, green: 1.0, blue: 0.86).opacity(0.54),
                                        .white.opacity(0.88),
                                        Color(red: 1.0, green: 0.76, blue: 0.28).opacity(0.68),
                                        Color(red: 1.0, green: 0.13, blue: 0.31).opacity(0.44),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 174, height: 1)
                            .opacity(0.30 + entryProgress * 0.70)
                            .scaleEffect(x: 0.18 + entryProgress * 0.82, y: 1, anchor: .center)

                        Text("YOUR MUSIC, YOUR SPACE")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .opacity(entryProgress)
                    .scaleEffect(0.94 + entryProgress * 0.06)
                    .offset(y: (1 - entryProgress) * 12)
                    .compositingGroup()
                }
                .background(Color(red: 0.002, green: 0.004, blue: 0.005))
                .compositingGroup()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static func easeOutCubic(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }
}
