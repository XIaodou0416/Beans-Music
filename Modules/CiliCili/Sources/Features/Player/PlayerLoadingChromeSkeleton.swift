import SwiftUI

struct PlayerLoadingChromeSkeleton: View {
    private let metrics = PlayerNativeControlMetrics.portrait
    private let visibleProgressHeight: CGFloat = 3

    var body: some View {
        ZStack {
            topLeadingBackControl
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 10)
                .padding(.leading, 10)

            bottomControls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .opacity(0.36)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topLeadingBackControl: some View {
        Circle()
            .fill(Color.white.opacity(0.16))
            .frame(width: metrics.controlHeight, height: metrics.controlHeight)
    }

    private var bottomControls: some View {
        VStack(spacing: metrics.stackSpacing) {
            Capsule()
                .fill(Color.white.opacity(0.20))
                .frame(height: visibleProgressHeight)
                .frame(height: metrics.progressControlHeight, alignment: .center)
                .padding(.horizontal, metrics.sliderHorizontalPadding)

            HStack(spacing: metrics.controlSpacing) {
                skeletonCircle

                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: metrics.timeLabelWidth, height: metrics.controlHeight)

                Spacer(minLength: 0)

                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: metrics.qualityButtonMaxWidth, height: metrics.controlHeight)

                skeletonCircle
                skeletonCircle
            }
            .frame(height: metrics.controlHeight)
        }
    }

    private var skeletonCircle: some View {
        Circle()
            .fill(Color.white.opacity(0.16))
            .frame(width: metrics.controlHeight, height: metrics.controlHeight)
    }
}
