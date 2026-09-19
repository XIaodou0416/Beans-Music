import SwiftUI

/// A low-cost launch field inspired by the reference's dark, diagonal light bands.
/// The text is composed in the same SwiftUI layer so the mark and the animation
/// fade together instead of appearing on separate planes.
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
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = Float(context.date.timeIntervalSince(start))
            Color.black
                .colorEffect(
                    Shader(
                        function: ShaderFunction(library: .default, name: "beansAnimatedBands"),
                        arguments: [
                            .boundingRect,
                            .float(elapsed),
                            .float(0.035),
                            .float(0.52),
                            .float(0.14),
                            .float(0.24),
                            .color(Color(red: 0.78, green: 0.67, blue: 0.43)),
                            .color(Color(red: 0.32, green: 0.59, blue: 0.52)),
                            .color(Color(red: 0.72, green: 0.38, blue: 0.43)),
                            .color(Color(red: 0.44, green: 0.42, blue: 0.58))
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
    var body: some View {
        ZStack {
            BeansAnimatedLoop()
                .opacity(0.94)

            VStack(spacing: 14) {
                Text("Beans Music")
                    .font(BeansFont.appFont(66, .bold))
                    .minimumScaleFactor(0.58)
                    .lineLimit(1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .white,
                                Color(red: 0.74, green: 0.88, blue: 0.80),
                                Color(red: 0.88, green: 0.70, blue: 0.42)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .black.opacity(0.72), radius: 22, y: 12)

                Rectangle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 170, height: 1)

                Text("PRIVATE VISUAL RADIO")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kerning(3.2)
                    .foregroundStyle(.white.opacity(0.48))

                Text("Beans Music")
                    .font(BeansFont.appFont(19, .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .compositingGroup()
        }
        .background(Color.black)
        .compositingGroup()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
