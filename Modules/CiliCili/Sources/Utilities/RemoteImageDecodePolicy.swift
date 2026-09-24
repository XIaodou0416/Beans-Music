import CoreGraphics

nonisolated enum RemoteImageDecodePolicy: Hashable, Sendable {
    case standard
    case highQualityViewer
}

nonisolated enum RemoteImageDecodeSizing {
    static let highQualityViewerMaximumPixelSize = 16_000

    static func effectiveTargetPixelSize(
        _ targetPixelSize: Int?,
        scale: CGFloat,
        policy: RemoteImageDecodePolicy,
        environment: PlaybackEnvironment
    ) -> Int {
        let requested = targetPixelSize ?? Int((1_200 * max(scale, 1)).rounded(.up))
        if policy == .highQualityViewer {
            return max(96, min(requested, highQualityViewerMaximumPixelSize))
        }

        let defaultMaximumPixelSize: Int
        if environment.isLowPowerModeEnabled || environment.isThermallyConstrained {
            defaultMaximumPixelSize = 640
        } else {
            switch environment.networkClass {
            case .wifi, .unknown:
                defaultMaximumPixelSize = 1_280
            case .cellular, .constrained:
                defaultMaximumPixelSize = 760
            }
        }

        let maximumPixelSize: Int
        if targetPixelSize == nil {
            maximumPixelSize = defaultMaximumPixelSize
        } else if environment.isLowPowerModeEnabled || environment.isThermallyConstrained {
            maximumPixelSize = 960
        } else {
            switch environment.networkClass {
            case .wifi, .unknown:
                maximumPixelSize = 2_600
            case .cellular, .constrained:
                maximumPixelSize = 1_024
            }
        }
        return max(96, min(requested, maximumPixelSize))
    }
}
