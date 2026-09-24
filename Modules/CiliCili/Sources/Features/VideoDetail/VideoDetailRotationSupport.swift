import UIKit

nonisolated enum VideoDetailSurfaceChromePolicy {
    static func showsFullscreenStatusControls(
        usesFullscreenChrome: Bool,
        isPortraitFullscreen: Bool
    ) -> Bool {
        usesFullscreenChrome && !isPortraitFullscreen
    }
}

nonisolated struct VideoDetailRotationRequestCoalescer {
    private(set) var isTransitioning = false
    private(set) var pendingTarget: UIInterfaceOrientationMask?

    mutating func beginTransition() {
        isTransitioning = true
    }

    mutating func submit(
        _ target: UIInterfaceOrientationMask
    ) -> UIInterfaceOrientationMask? {
        guard isTransitioning else { return target }
        pendingTarget = target
        return nil
    }

    mutating func completeTransition(
        currentOrientation: UIInterfaceOrientation
    ) -> UIInterfaceOrientationMask? {
        isTransitioning = false
        defer { pendingTarget = nil }
        guard let pendingTarget,
              !pendingTarget.contains(Self.mask(for: currentOrientation))
        else { return nil }
        return pendingTarget
    }

    mutating func reset() {
        isTransitioning = false
        pendingTarget = nil
    }

    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return []
        }
    }
}

nonisolated struct VideoDetailRotationPolicy: Equatable {
    func hidesContentHost(duringTransitionToLandscape _: Bool) -> Bool {
        false
    }

    var publishesContentLayoutDuringSystemTransition: Bool {
        false
    }

    var hidesPlaybackControlsDuringSystemTransition: Bool {
        true
    }

    func usesPrewarmedFastRecovery(hasPrewarmedRotationChrome: Bool) -> Bool {
        hasPrewarmedRotationChrome
    }

    func restoresPortraitAfterResolvingPortraitVideo(isCurrentlyLandscape: Bool) -> Bool {
        isCurrentlyLandscape
    }

    func preferredLandscapeInterfaceOrientation(
        currentInterfaceOrientation: UIInterfaceOrientation?,
        deviceOrientation: UIDeviceOrientation
    ) -> UIInterfaceOrientationMask {
        if currentInterfaceOrientation == .landscapeLeft {
            return .landscapeLeft
        }
        if currentInterfaceOrientation == .landscapeRight {
            return .landscapeRight
        }

        switch deviceOrientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .landscapeRight
        }
    }
}

nonisolated struct VideoDetailRotationRecoveryPolicy: Equatable {
    func watchdogDelay(coordinatorDuration: TimeInterval) -> TimeInterval {
        max(1.25, coordinatorDuration + 0.75)
    }

    func resolvesLandscape(
        interfaceOrientation: UIInterfaceOrientation?,
        fallbackBounds: CGSize
    ) -> Bool {
        switch interfaceOrientation {
        case .landscapeLeft, .landscapeRight:
            return true
        case .portrait, .portraitUpsideDown:
            return false
        default:
            return fallbackBounds.width > fallbackBounds.height
        }
    }
}
