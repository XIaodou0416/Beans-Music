import CoreMedia
import Foundation
import Network
import VideoToolbox

nonisolated struct PlaybackEnvironment: Sendable {
    enum NetworkClass: Sendable, Equatable {
        case wifi
        case cellular
        case constrained
        case unknown
    }

    enum ThermalPressure: Int, Sendable, Equatable {
        case nominal
        case fair
        case elevated
        case critical
    }

    let networkClass: NetworkClass
    let isLowPowerModeEnabled: Bool
    let isThermallyConstrained: Bool
    let thermalPressure: ThermalPressure

    nonisolated static var current: PlaybackEnvironment {
        let thermalState = ProcessInfo.processInfo.thermalState
        let pressure: ThermalPressure
        switch thermalState {
        case .nominal:
            pressure = .nominal
        case .fair:
            pressure = .fair
        case .serious:
            pressure = .elevated
        case .critical:
            pressure = .critical
        @unknown default:
            pressure = .nominal
        }
        return PlaybackEnvironment(
            networkClass: NetworkPathSnapshot.shared.currentNetworkClass,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isThermallyConstrained: pressure.rawValue >= ThermalPressure.elevated.rawValue,
            thermalPressure: pressure
        )
    }

    nonisolated var isThermallyElevated: Bool {
        thermalPressure.rawValue >= ThermalPressure.fair.rawValue
    }

    nonisolated var shouldPreferConservativePlayback: Bool {
        let isConstrainedNetwork: Bool
        switch networkClass {
        case .cellular, .constrained:
            isConstrainedNetwork = true
        case .wifi, .unknown:
            isConstrainedNetwork = false
        }
        return isLowPowerModeEnabled
            || isThermallyConstrained
            || isConstrainedNetwork
    }

    nonisolated var preferredQualityLadder: [Int] {
        if shouldPreferConservativePlayback {
            return [64, 32, 16, 6]
        }
        return [80, 64, 32, 16, 6]
    }

    nonisolated var preferredForwardBufferDuration: TimeInterval {
        if shouldPreferConservativePlayback {
            switch networkClass {
            case .wifi, .unknown:
                return 0.55
            case .cellular, .constrained:
                return 0.45
            }
        }
        switch networkClass {
        case .wifi:
            return 1.15
        case .unknown:
            return 0.9
        case .cellular, .constrained:
            return 0.45
        }
    }

    nonisolated var separatedTrackForwardBufferDuration: TimeInterval {
        if shouldPreferConservativePlayback {
            switch networkClass {
            case .wifi, .unknown:
                return 0.75
            case .cellular, .constrained:
                return 0.6
            }
        }
        switch networkClass {
        case .wifi:
            return 1.35
        case .unknown:
            return 1.0
        case .cellular, .constrained:
            return 0.6
        }
    }

    nonisolated var startupForwardBufferDuration: TimeInterval {
        switch networkClass {
        case .wifi:
            return shouldPreferConservativePlayback ? 0.10 : 0.06
        case .unknown:
            return shouldPreferConservativePlayback ? 0.12 : 0.08
        case .cellular, .constrained:
            return 0.14
        }
    }

    nonisolated var highRateForwardBufferDuration: TimeInterval {
        shouldPreferConservativePlayback ? 2.0 : 3.2
    }

    nonisolated var maxBufferDuration: TimeInterval {
        shouldPreferConservativePlayback ? 3.2 : 5.0
    }

    nonisolated var preferredPlayURLStartupGrace: UInt64 {
        switch networkClass {
        case .wifi:
            return 180_000_000
        case .unknown:
            return 140_000_000
        case .cellular, .constrained:
            return 80_000_000
        }
    }

    nonisolated var diagnosticSummary: String {
        let networkTitle: String
        switch networkClass {
        case .wifi:
            networkTitle = "Wi-Fi"
        case .cellular:
            networkTitle = "蜂窝网络"
        case .constrained:
            networkTitle = "受限网络"
        case .unknown:
            networkTitle = "未知网络"
        }
        var parts = [networkTitle]
        if isLowPowerModeEnabled {
            parts.append("省电")
        }
        if isThermallyConstrained {
            parts.append("温控")
        } else if isThermallyElevated {
            parts.append("温热")
        }
        if shouldPreferConservativePlayback {
            parts.append("保守")
        }
        return parts.joined(separator: " · ")
    }
}

extension PlaybackEnvironment.NetworkClass {
    nonisolated var performanceSampleKey: String {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .constrained:
            return "constrained"
        case .unknown:
            return "unknown"
        }
    }

    nonisolated var performanceSampleTitle: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "蜂窝网络"
        case .constrained:
            return "受限网络"
        case .unknown:
            return "未知网络"
        }
    }
}

nonisolated enum AV1HardwareDecodeProbeResult: Equatable, Sendable {
    case supported
    case unsupported
    case simulator

    var isSupported: Bool {
        self == .supported
    }

    var settingsStatusTitle: String {
        switch self {
        case .supported:
            return "可用"
        case .unsupported:
            return "不支持"
        case .simulator:
            return "模拟器"
        }
    }

    var detail: String {
        switch self {
        case .supported:
            return "系统已确认此设备支持 AV1 硬解。首选编码中可以选择“优先 AV1”，没有 AV1 视频流时会自动降级。"
        case .unsupported:
            return "系统未报告 AV1 硬解能力。为避免软件解码造成耗电、发热或卡顿，应用不会提供 AV1 播放选项。"
        case .simulator:
            return "iOS 模拟器不提供可用的 AV1 硬解能力。请在真机上检测。"
        }
    }
}

nonisolated enum PlaybackCodecPolicy {
    nonisolated static var av1HardwareDecodeProbe: AV1HardwareDecodeProbeResult {
#if targetEnvironment(simulator)
        return .simulator
#else
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) ? .supported : .unsupported
#endif
    }

    nonisolated static var canDecodeAV1: Bool {
        av1HardwareDecodeProbe.isSupported
    }

    nonisolated static var canDecodeHEVC: Bool {
#if targetEnvironment(simulator)
        return true
#else
        VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
#endif
    }

    nonisolated static var canDecodeHDRVideo: Bool {
#if targetEnvironment(simulator)
        return false
#else
        return canDecodeHEVC
#endif
    }

    nonisolated static func canDecode(dynamicRange: BiliVideoDynamicRange) -> Bool {
        switch dynamicRange {
        case .sdr:
            return true
        case .hdr10, .hlg, .dolbyVision:
            return canDecodeHDRVideo
        }
    }

    nonisolated static func unsupportedDynamicRangeReason(for dynamicRange: BiliVideoDynamicRange) -> String? {
        guard !canDecode(dynamicRange: dynamicRange) else { return nil }
#if targetEnvironment(simulator)
        return "模拟器暂不支持 HDR/Dolby"
#else
        return "当前设备暂不可播"
#endif
    }

    nonisolated static var requiresHEVCPlayback: Bool {
        true
    }

    nonisolated static var allowsNonHEVCHardwareFallback: Bool {
        true
    }

    nonisolated static var requiresAACAudioPlayback: Bool {
        true
    }
}

final class NetworkPathSnapshot: @unchecked Sendable {
    nonisolated static let shared = NetworkPathSnapshot()

    nonisolated private let monitor = NWPathMonitor()
    nonisolated private let queue = DispatchQueue(label: "cc.bili.network-path")
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var cachedClass: PlaybackEnvironment.NetworkClass = .unknown
    nonisolated(unsafe) private var cachedUsesCellular = false

    nonisolated private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path)
        }
        monitor.start(queue: queue)
    }

    nonisolated var currentNetworkClass: PlaybackEnvironment.NetworkClass {
        lock.withLock { cachedClass }
    }

    nonisolated var usesCellular: Bool {
        lock.withLock { cachedUsesCellular }
    }

    nonisolated private func update(_ path: NWPath) {
        let usesCellular = path.usesInterfaceType(.cellular)
        let value: PlaybackEnvironment.NetworkClass
        if path.isConstrained {
            value = .constrained
        } else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            value = .wifi
        } else if usesCellular {
            value = .cellular
        } else {
            value = .unknown
        }
        let didChange = lock.withLock {
            let previous = cachedClass
            let previousUsesCellular = cachedUsesCellular
            guard previous != value || previousUsesCellular != usesCellular else { return false }
            cachedClass = value
            cachedUsesCellular = usesCellular
            return true
        }
        if didChange {
            DispatchQueue.main.async {
                StageOneBaselineMetricsStore.shared.recordNetworkRawChange()
                NotificationCenter.default.post(name: .biliPlaybackNetworkClassDidChange, object: self)
            }
        }
    }
}

extension Notification.Name {
    static let biliPlaybackNetworkClassDidChange = Notification.Name("cc.bili.playbackNetworkClassDidChange")
}

private extension NSLock {
    nonisolated func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
