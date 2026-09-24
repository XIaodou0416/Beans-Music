import SwiftUI

struct PlayerNativeProgressGestureCaptureLayer: View {
    let isEnabled: Bool
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled else { return }
                            onScrubChanged(progress(for: value.location.x, width: proxy.size.width))
                        }
                        .onEnded { value in
                            if isEnabled {
                                onScrubEnded(progress(for: value.location.x, width: proxy.size.width))
                            }
                        }
                )
                .allowsHitTesting(isEnabled)
        }
    }

    private func progress(for locationX: CGFloat, width: CGFloat) -> Double {
        PlayerNativeProgressScrubCalculator.progress(locationX: locationX, width: width)
    }
}
