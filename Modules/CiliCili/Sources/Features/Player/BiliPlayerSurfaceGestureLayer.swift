import SwiftUI

struct BiliPlayerSurfaceGestureLayer<Content: View>: View {
    let content: Content
    let clock: PlayerPlaybackClock
    let durationHint: TimeInterval?
    let canSeek: Bool
    let allowsDoubleTapPlaybackToggle: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onBeginSpeedBoost: () -> Bool
    let onEndSpeedBoost: (PlayerSpeedBoostEndReason) -> Void
    let onHorizontalSeekStart: (Double) -> Void
    let onHorizontalSeekChanged: (Double) -> Void
    let onHorizontalSeekEnded: (Double) -> Void
    let onHorizontalSeekCancelled: () -> Void
    let onHorizontalSeekCancelPendingChanged: (Bool) -> Void

    @State private var horizontalSeekStartProgress: Double?
    @State private var horizontalSeekCurrentProgress: Double?
    @State private var horizontalSeekLastTranslationWidth: CGFloat?
    @State private var isHorizontalSeeking = false
    @State private var isHorizontalSeekCancelPending = false
    @State private var isSpeedBoostGestureActive = false
    @State private var didAttemptSpeedBoost = false
    @StateObject private var systemControlsController = PlayerSystemControlsController()
    @State private var verticalAdjustmentTarget: PlayerSurfaceVerticalAdjustmentTarget?
    @State private var verticalAdjustmentStartValue: Float?
    @State private var verticalAdjustmentValue: Float?
    @State private var isVerticalAdjusting = false
    @State private var hardwareVolumeIndicatorValue: Float?
    @State private var hardwareVolumeIndicatorDismissTask: Task<Void, Never>?
    @State private var lastGestureRequestedVolume: Float?

    private let horizontalSeekActivationDistance: CGFloat = 8
    private let horizontalSeekDominanceRatio: CGFloat = 3
    private let verticalAdjustmentActivationDistance: CGFloat = 8
    private let verticalAdjustmentDominanceRatio: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            tappableContent(size: proxy.size)
                .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.28, maximumDistance: 80)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        guard !isHorizontalSeeking, !isVerticalAdjusting else { return }
                        guard case .second(true, _) = value else { return }
                        guard !didAttemptSpeedBoost else { return }
                        didAttemptSpeedBoost = true
                        isSpeedBoostGestureActive = onBeginSpeedBoost()
                    }
                    .onEnded { _ in
                        let wasSpeedBoostActive = isSpeedBoostGestureActive
                        isSpeedBoostGestureActive = false
                        didAttemptSpeedBoost = false
                        if wasSpeedBoostActive {
                            onEndSpeedBoost(.gestureEnded)
                        }
                    }
            )
            .simultaneousGesture(horizontalSeekGesture(size: proxy.size))
            .simultaneousGesture(verticalAdjustmentGesture(size: proxy.size))
        }
        .accessibilityElement()
        .accessibilityLabel("播放器画面")
        .accessibilityIdentifier("ui.player.surface")
        .accessibilityAction {
            onSingleTap()
        }
    }

    @ViewBuilder
    private func tappableContent(size: CGSize) -> some View {
        if allowsDoubleTapPlaybackToggle {
            playerContent
                .simultaneousGesture(tapGesture(size: size))
        } else {
            playerContent
                .simultaneousGesture(singleTapGesture)
        }
    }

    private var playerContent: some View {
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PlayerSystemControlsHost(controller: systemControlsController)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if isVerticalAdjusting,
               let verticalAdjustmentTarget,
               let verticalAdjustmentValue {
                PlayerSurfaceVerticalAdjustmentIndicator(
                    target: verticalAdjustmentTarget,
                    value: verticalAdjustmentValue
                )
                .allowsHitTesting(false)
            } else if let hardwareVolumeIndicatorValue {
                PlayerSurfaceVerticalAdjustmentIndicator(
                    target: .volume,
                    value: hardwareVolumeIndicatorValue
                )
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onChange(of: systemControlsController.outputVolume) { previousValue, currentValue in
            handleOutputVolumeChange(previousValue: previousValue, currentValue: currentValue)
        }
        .onDisappear {
            dismissHardwareVolumeIndicator()
        }
    }

    private var singleTapGesture: some Gesture {
        SpatialTapGesture(count: 1, coordinateSpace: .local)
            .onEnded { _ in
                onSingleTap()
            }
    }

    private func horizontalSeekGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: horizontalSeekActivationDistance, coordinateSpace: .local)
            .onChanged { value in
                guard canSeek, !isSpeedBoostGestureActive, !isVerticalAdjusting else { return }
                updateHorizontalSeek(for: value, size: size)
            }
            .onEnded { value in
                guard canSeek, isHorizontalSeeking else {
                    if isHorizontalSeeking {
                        onHorizontalSeekCancelled()
                    }
                    resetHorizontalSeekState(clearsClockPreview: true)
                    return
                }
                updateHorizontalSeek(for: value, size: size)
                guard !isHorizontalSeekCancelPending else {
                    onHorizontalSeekCancelled()
                    resetHorizontalSeekState(clearsClockPreview: true)
                    return
                }
                let progress = horizontalSeekCurrentProgress
                    ?? horizontalSeekStartProgress
                    ?? clock.progress
                onHorizontalSeekEnded(progress)
                resetHorizontalSeekState(clearsClockPreview: false)
            }
    }

    private func verticalAdjustmentGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: verticalAdjustmentActivationDistance, coordinateSpace: .local)
            .onChanged { value in
                guard !isHorizontalSeeking, !isSpeedBoostGestureActive else { return }
                updateVerticalAdjustment(for: value, size: size)
            }
            .onEnded { _ in
                resetVerticalAdjustmentState()
            }
    }

    private func tapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .exclusively(before: SpatialTapGesture(count: 1, coordinateSpace: .local))
            .onEnded { value in
                switch value {
                case .first(let doubleTap):
                    guard PlayerDoubleTapGesturePolicy.shouldTogglePlayback(
                        locationX: doubleTap.location.x,
                        width: size.width
                    ) else { return }
                    onDoubleTap()
                case .second:
                    onSingleTap()
                }
            }
    }

    private func updateHorizontalSeek(for value: DragGesture.Value, size: CGSize) {
        guard let duration = resolvedDuration, duration > 0 else { return }
        guard size.width > 0 else { return }
        let dx = value.translation.width
        let dy = value.translation.height
        if !isHorizontalSeeking {
            guard PlayerSurfaceGestureAxisPolicy.axis(
                translation: CGSize(width: dx, height: dy),
                activationDistance: horizontalSeekActivationDistance,
                dominanceRatio: horizontalSeekDominanceRatio
            ) == .horizontal else { return }
            let startProgress = clock.progress
            isHorizontalSeeking = true
            horizontalSeekStartProgress = startProgress
            horizontalSeekCurrentProgress = startProgress
            horizontalSeekLastTranslationWidth = dx
            isHorizontalSeekCancelPending = horizontalSeekShouldCancel(at: value.location, size: size)
            clock.updateSeekPreview(progress: startProgress, force: true)
            onHorizontalSeekStart(startProgress)
            onHorizontalSeekCancelPendingChanged(isHorizontalSeekCancelPending)
            return
        }

        let previousTranslationWidth = horizontalSeekLastTranslationWidth ?? dx
        horizontalSeekLastTranslationWidth = dx
        let deltaX = dx - previousTranslationWidth
        let currentProgress = horizontalSeekCurrentProgress
            ?? horizontalSeekStartProgress
            ?? clock.progress
        let secondsPerFullWidth = PlayerHorizontalSeekSensitivity.secondsPerFullWidth(duration: duration)
        let progressDelta = Double(deltaX / size.width) * secondsPerFullWidth / duration
        let progress = min(max(currentProgress + progressDelta, 0), 1)
        horizontalSeekCurrentProgress = progress
        clock.updateSeekPreview(progress: progress)
        isHorizontalSeekCancelPending = horizontalSeekShouldCancel(at: value.location, size: size)
        onHorizontalSeekCancelPendingChanged(isHorizontalSeekCancelPending)
        onHorizontalSeekChanged(progress)
    }

    private func updateVerticalAdjustment(for value: DragGesture.Value, size: CGSize) {
        if !isVerticalAdjusting {
            guard PlayerSurfaceVerticalAdjustmentPolicy.shouldBegin(
                translation: value.translation,
                activationDistance: verticalAdjustmentActivationDistance,
                dominanceRatio: verticalAdjustmentDominanceRatio
            ),
            let target = PlayerSurfaceVerticalAdjustmentPolicy.target(
                startLocationX: value.startLocation.x,
                width: size.width
            )
            else { return }

            guard let startValue = systemValue(for: target) else { return }
            isVerticalAdjusting = true
            dismissHardwareVolumeIndicator()
            verticalAdjustmentTarget = target
            verticalAdjustmentStartValue = startValue
        }

        guard let target = verticalAdjustmentTarget,
              let startValue = verticalAdjustmentStartValue
        else { return }

        let value = PlayerSurfaceVerticalAdjustmentPolicy.adjustedValue(
            initialValue: startValue,
            verticalTranslation: value.translation.height,
            height: size.height
        )
        verticalAdjustmentValue = value
        applySystemValue(value, for: target)
    }

    private func resetVerticalAdjustmentState() {
        isVerticalAdjusting = false
        verticalAdjustmentTarget = nil
        verticalAdjustmentStartValue = nil
        verticalAdjustmentValue = nil
    }

    private func systemValue(for target: PlayerSurfaceVerticalAdjustmentTarget) -> Float? {
        switch target {
        case .brightness:
            return systemControlsController.displayBrightness
        case .volume:
            return systemControlsController.outputVolume
        }
    }

    private func applySystemValue(_ value: Float, for target: PlayerSurfaceVerticalAdjustmentTarget) {
        switch target {
        case .brightness:
            systemControlsController.setDisplayBrightness(value)
        case .volume:
            lastGestureRequestedVolume = value
            systemControlsController.setOutputVolume(value)
        }
    }

    private func handleOutputVolumeChange(previousValue: Float, currentValue: Float) {
        if isVerticalAdjusting {
            return
        }
        if let lastGestureRequestedVolume,
           abs(lastGestureRequestedVolume - currentValue) <= 0.0001 {
            self.lastGestureRequestedVolume = nil
            return
        }
        lastGestureRequestedVolume = nil
        guard PlayerSurfaceVerticalAdjustmentPolicy.shouldPresentHardwareVolumeIndicator(
            previousValue: previousValue,
            currentValue: currentValue,
            isVerticalAdjusting: isVerticalAdjusting
        ) else { return }

        hardwareVolumeIndicatorDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) {
            hardwareVolumeIndicatorValue = currentValue
        }
        hardwareVolumeIndicatorDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                hardwareVolumeIndicatorValue = nil
            }
        }
    }

    private func dismissHardwareVolumeIndicator() {
        hardwareVolumeIndicatorDismissTask?.cancel()
        hardwareVolumeIndicatorDismissTask = nil
        hardwareVolumeIndicatorValue = nil
    }

    private var resolvedDuration: TimeInterval? {
        clock.duration ?? durationHint
    }

    private func resetHorizontalSeekState(clearsClockPreview: Bool) {
        horizontalSeekStartProgress = nil
        horizontalSeekCurrentProgress = nil
        horizontalSeekLastTranslationWidth = nil
        isHorizontalSeeking = false
        isHorizontalSeekCancelPending = false
        if clearsClockPreview {
            clock.clearSeekPreview()
        }
    }

    private func horizontalSeekShouldCancel(at location: CGPoint, size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let topCancelHeight = size.height * 0.125
        let edgeCancelWidth = size.width * 0.125
        return location.y <= topCancelHeight
            && (location.x <= edgeCancelWidth || location.x >= size.width - edgeCancelWidth)
    }
}

struct PlayerSurfaceVerticalAdjustmentIndicator: View {
    let target: PlayerSurfaceVerticalAdjustmentTarget
    let value: Float

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            ProgressView(value: Double(value), total: 1)
                .tint(.white)
                .frame(width: 86)
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .padding(14)
        .frame(minWidth: 112)
        .biliPlayerClearGlass(interactive: false, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(target.accessibilityLabel)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var systemImage: String {
        switch target {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if value <= 0.01 { return "speaker.slash.fill" }
            return value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
        }
    }
}
