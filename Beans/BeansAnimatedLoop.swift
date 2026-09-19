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
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = Float(context.date.timeIntervalSince(start))
            Color.black
                .colorEffect(
                    Shader(
                        function: ShaderFunction(library: .default, name: "beansAnimatedLoop"),
                        arguments: [
                            .boundingRect,
                            .float(elapsed),
                            .float(0.055),
                            .float(0.0018),
                            .float(6),
                            .float(4.8),
                            .float(0.012),
                            .float(0.2),
                            .float(0.0),
                            .float(1.0),
                            .float2(0.0, 0.0),
                            .float(0),
                            .float(0),
                            .color(Color(red: 0.35, green: 0.78, blue: 1.0)),
                            .color(Color(red: 0.72, green: 0.45, blue: 1.0)),
                            .color(Color(red: 1.0, green: 0.45, blue: 0.66)),
                            .color(.black)
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
        BeansAnimatedLoop()
            .opacity(0.86)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: Color.beansHighlight.opacity(0.65), radius: 18)
                    Text("Beans Music")
                        .font(BeansFont.appFont(22, .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                }
                .compositingGroup()
            }
            .background(Color.black)
            .compositingGroup()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
