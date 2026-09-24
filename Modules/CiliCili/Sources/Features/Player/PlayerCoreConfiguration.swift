import Combine
import Foundation

typealias DashStream = DASHStream

struct VideoCodecPreference: Identifiable, Codable, Equatable, Sendable {
    nonisolated static let storageKey = "cc.bili.playback.videoCodecPreference.v1"
    nonisolated static let defaultValue = VideoCodecPreference(codecOrder: [.hevc, .h264])
    nonisolated static let auto = defaultValue
    nonisolated static let preferAV1 = VideoCodecPreference(codecOrder: [.av1, .hevc, .h264])
    nonisolated static let forceHEVC = VideoCodecPreference(codecOrder: [.hevc])
    nonisolated static let forceH264 = VideoCodecPreference(codecOrder: [.h264])

    let codecOrder: [VideoCodecFamily]

    nonisolated init(codecOrder: [VideoCodecFamily]) {
        var seen = Set<VideoCodecFamily>()
        let normalized = codecOrder.filter {
            $0 != .unknown && seen.insert($0).inserted
        }
        self.codecOrder = normalized.isEmpty ? Self.defaultCodecOrder : normalized
    }

    nonisolated var id: String { rawValue }

    nonisolated var rawValue: String {
        codecOrder.map(\.storageToken).joined(separator: ",")
    }

    nonisolated var title: String {
        if codecOrder.count == 1, let codec = codecOrder.first {
            return "仅 \(codec.title)"
        }
        return codecOrder.map(\.title).joined(separator: " → ")
    }

    nonisolated var detail: String {
        "按 \(codecOrder.map(\.title).joined(separator: "、")) 的顺序自动选择；关闭的编码不会参与播放。"
    }

    nonisolated var forcedCodecFamily: VideoCodecFamily? {
        codecOrder.count == 1 ? codecOrder.first : nil
    }

    nonisolated var forcedUnavailableMessage: String? {
        guard let forcedCodecFamily else { return nil }
        return "当前视频没有可硬解 \(forcedCodecFamily.title) 播放地址，可在设置中启用其他编码。"
    }

    nonisolated static func stored(in userDefaults: UserDefaults = .standard) -> VideoCodecPreference {
        guard let rawValue = userDefaults.string(forKey: storageKey) else {
            return defaultValue
        }
        let storedPreference: VideoCodecPreference
        switch rawValue {
        case "auto":
            storedPreference = .auto
        case "forceAV1", "preferAV1":
            storedPreference = .preferAV1
        case "forceHEVC":
            storedPreference = .forceHEVC
        case "forceH264":
            storedPreference = .forceH264
        default:
            storedPreference = VideoCodecPreference(
                codecOrder: rawValue
                    .split(separator: ",")
                    .compactMap { VideoCodecFamily(storageToken: String($0)) }
            )
        }
        let resolvedPreference = storedPreference.resolvedForCurrentDevice
        if rawValue != resolvedPreference.rawValue {
            userDefaults.set(resolvedPreference.rawValue, forKey: storageKey)
        }
        return resolvedPreference
    }

    nonisolated var isAvailableOnCurrentDevice: Bool {
        !codecOrder.contains(.av1) || PlaybackCodecPolicy.canDecodeAV1
    }

    nonisolated var resolvedForCurrentDevice: VideoCodecPreference {
        guard !isAvailableOnCurrentDevice else { return self }
        return VideoCodecPreference(codecOrder: codecOrder.filter { $0 != .av1 })
    }

    private nonisolated static let defaultCodecOrder: [VideoCodecFamily] = [.hevc, .h264]
}

enum VideoCodecFamily: Int, CaseIterable, Codable, Identifiable, Sendable {
    case unknown = 0
    case h264 = 1
    case hevc = 2
    case av1 = 3

    nonisolated var id: Int { rawValue }

    nonisolated static let configurableCases: [VideoCodecFamily] = [.av1, .hevc, .h264]

    nonisolated var title: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        case .av1:
            return "AV1"
        }
    }

    nonisolated var storageToken: String {
        switch self {
        case .unknown:
            return "unknown"
        case .h264:
            return "h264"
        case .hevc:
            return "hevc"
        case .av1:
            return "av1"
        }
    }

    nonisolated init?(storageToken: String) {
        switch storageToken.lowercased() {
        case "h264", "avc", "avc1":
            self = .h264
        case "hevc", "hvc1", "hev1":
            self = .hevc
        case "av1", "av01":
            self = .av1
        default:
            return nil
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .unknown:
            return "questionmark.square"
        case .h264:
            return "rectangle.compress.vertical"
        case .hevc:
            return "rectangle.stack"
        case .av1:
            return "sparkles.tv"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .unknown:
            return "未知编码"
        case .h264:
            return "兼容性最好，通常文件更大。"
        case .hevc:
            return "画质和体积均衡，Apple 设备硬解成熟。"
        case .av1:
            return PlaybackCodecPolicy.canDecodeAV1
                ? "压缩效率更高，当前设备支持硬解。"
                : "当前设备未检测到 AV1 硬解能力。"
        }
    }

    nonisolated var isAvailableOnCurrentDevice: Bool {
        self != .av1 || PlaybackCodecPolicy.canDecodeAV1
    }
}

nonisolated enum DashStreamDispatcher {
    static func selectBestStream(
        from streams: [DashStream],
        preference: VideoCodecPreference,
        supportsAV1HardwareDecode: Bool = PlaybackCodecPolicy.canDecodeAV1
    ) -> DashStream? {
        let enabledFamilies = Set(preference.codecOrder)
        let playableStreams = streams.enumerated()
            .filter { _, stream in
                guard stream.url != nil else { return false }
                guard stream.videoCodecFamily != .av1 || supportsAV1HardwareDecode else { return false }
                return enabledFamilies.contains(stream.videoCodecFamily)
            }
        guard !playableStreams.isEmpty else { return nil }

        let streams = playableStreams.map(\.element)
        let codecOrder = effectiveCodecOrder(
            for: preference,
            streams: streams
        )
        return playableStreams
            .min { lhs, rhs in
                rankingTuple(
                    for: lhs.element,
                    originalIndex: lhs.offset,
                    codecOrder: codecOrder
                ) < rankingTuple(
                    for: rhs.element,
                    originalIndex: rhs.offset,
                    codecOrder: codecOrder
                )
            }?
            .element
    }

    private static func effectiveCodecOrder(
        for preference: VideoCodecPreference,
        streams _: [DashStream] = []
    ) -> [VideoCodecFamily] {
        return preference.codecOrder
    }

    private static func rankingTuple(
        for stream: DashStream,
        originalIndex: Int,
        codecOrder: [VideoCodecFamily]
    ) -> StreamRankingTuple {
        let family = stream.videoCodecFamily
        let codecIndex = codecOrder.firstIndex(of: family) ?? codecOrder.count
        return StreamRankingTuple(
            codecIndex: codecIndex,
            dolbyPenalty: stream.isDolbyVisionVideoCodec ? 1 : 0,
            hardwarePenalty: stream.isHardwareDecodingCompatibleVideo ? 0 : 1,
            negativeBandwidth: -(stream.bandwidth ?? 0),
            originalIndex: originalIndex
        )
    }

}

nonisolated private struct StreamRankingTuple: Comparable {
    let codecIndex: Int
    let dolbyPenalty: Int
    let hardwarePenalty: Int
    let negativeBandwidth: Int
    let originalIndex: Int

    static func < (lhs: StreamRankingTuple, rhs: StreamRankingTuple) -> Bool {
        if lhs.codecIndex != rhs.codecIndex {
            return lhs.codecIndex < rhs.codecIndex
        }
        if lhs.dolbyPenalty != rhs.dolbyPenalty {
            return lhs.dolbyPenalty < rhs.dolbyPenalty
        }
        if lhs.hardwarePenalty != rhs.hardwarePenalty {
            return lhs.hardwarePenalty < rhs.hardwarePenalty
        }
        if lhs.negativeBandwidth != rhs.negativeBandwidth {
            return lhs.negativeBandwidth < rhs.negativeBandwidth
        }
        return lhs.originalIndex < rhs.originalIndex
    }
}

enum PlaybackHardwareDecodePolicy {
    nonisolated static let storageKey = "cc.bili.playback.forceHardwareDecode.v1"
    nonisolated static let defaultValue = true

    nonisolated static func stored(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

enum PlaybackAudioURLPolicy {
    nonisolated static let storageKey = "cc.bili.playback.prefersBackupAudioURL.v1"
    nonisolated static let defaultValue = false

    nonisolated static func stored(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

nonisolated enum DolbyVisionRenderingPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case compatibleHLG
    case metadataPassthrough
    case appleNativeP8HLS
    case protectedHLG
    /// Deprecated: Bilibili Profile 8.4 fMP4 streams fail AVPlayer startup when
    /// we advertise them as native `dvh1` HLS tracks.
    case fullEffect
    case supplementalHLS

    nonisolated static let storageKey = "cc.bili.playback.dolbyVisionRenderingPolicy.v1"
    nonisolated static let defaultValue: DolbyVisionRenderingPolicy = .appleNativeP8HLS
    nonisolated static let allCases: [DolbyVisionRenderingPolicy] = [
        .compatibleHLG,
        .appleNativeP8HLS
    ]

    nonisolated var id: String { rawValue }

    nonisolated var playablePolicy: DolbyVisionRenderingPolicy {
        switch self {
        case .compatibleHLG, .appleNativeP8HLS:
            return self
        case .metadataPassthrough, .protectedHLG, .fullEffect, .supplementalHLS:
            return .compatibleHLG
        }
    }

    nonisolated var hlsBridgePolicy: DolbyVisionRenderingPolicy {
        switch playablePolicy {
        case .appleNativeP8HLS:
            return .compatibleHLG
        case .compatibleHLG:
            return .compatibleHLG
        case .metadataPassthrough, .protectedHLG, .fullEffect, .supplementalHLS:
            return .compatibleHLG
        }
    }

    nonisolated var title: String {
        switch self {
        case .compatibleHLG:
            return "兼容基层防过曝"
        case .metadataPassthrough:
            return "已停用：杜比元数据直通"
        case .appleNativeP8HLS:
            return "原生 HDR 视频层（实验）"
        case .protectedHLG:
            return "已停用：杜比标识 + 过曝保护"
        case .fullEffect:
            return "已停用：原生杜比主轨"
        case .supplementalHLS:
            return "已停用：完整杜比视界实验"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .compatibleHLG:
            return "AVPlayer 只播放 Dolby Vision 的兼容基层，避免 B 站 Profile 8.4 触发过曝。"
        case .metadataPassthrough:
            return "该路线即使按色彩盒声明 HLG，AVPlayer 仍会因 B 站 Profile 8.4 元数据过曝，已自动迁移到兼容基层。"
        case .appleNativeP8HLS:
            return "底层 HLS 仍使用兼容基层，另挂一个静音 AVPlayerLayer 直连原始杜比/HDR 视频流，模拟 PiliPlus 的 iOS 原生显示链路。"
        case .protectedHLG:
            return "该路线仍可能让 AVPlayer 套用错误杜比映射，已自动迁移到兼容基层。"
        case .fullEffect:
            return "该路线会让 B 站 Profile 8.4 流不可播放，已自动迁移到兼容基层。"
        case .supplementalHLS:
            return "该路线会保留 Dolby Vision 补充标识并可能过曝，已自动迁移到兼容基层。"
        }
    }

    nonisolated static func stored(in userDefaults: UserDefaults = .standard) -> DolbyVisionRenderingPolicy {
        guard let rawValue = userDefaults.string(forKey: storageKey),
              let policy = DolbyVisionRenderingPolicy(rawValue: rawValue)
        else { return defaultValue }
        let playablePolicy = policy.playablePolicy
        if playablePolicy != policy {
            userDefaults.set(defaultValue.rawValue, forKey: storageKey)
            return defaultValue
        }
        return playablePolicy
    }
}

extension DASHStream {
    nonisolated init(
        id: Int?,
        url: URL,
        backupURLs: [URL] = [],
        bandwidth: Int? = nil,
        codecs: String?,
        codecid: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: String? = nil,
        mimeType: String? = nil,
        segmentBase: DASHSegmentBase? = nil
    ) {
        self.id = id
        self.baseURL = url.absoluteString
        self.backupURL = backupURLs.map(\.absoluteString)
        self.bandwidth = bandwidth
        self.codecs = codecs
        self.codecid = codecid
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.mimeType = mimeType
        self.segmentBase = segmentBase
    }

    nonisolated var url: URL? {
        playURL
    }

    nonisolated var videoCodecFamily: VideoCodecFamily {
        if isAV1VideoCodec {
            return .av1
        }
        if isHEVCVideoCodec {
            return .hevc
        }
        if isAVCVideoCodec {
            return .h264
        }
        return .unknown
    }
}

@MainActor
final class PlayerSettings: ObservableObject {
    static let shared = PlayerSettings()

    @Published private(set) var videoCodecPreference: VideoCodecPreference
    @Published private(set) var forceHardwareDecodeEnabled: Bool
    @Published private(set) var dolbyVisionRenderingPolicy: DolbyVisionRenderingPolicy

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.videoCodecPreference = VideoCodecPreference.stored(in: userDefaults)
        self.forceHardwareDecodeEnabled = PlaybackHardwareDecodePolicy.stored(in: userDefaults)
        self.dolbyVisionRenderingPolicy = DolbyVisionRenderingPolicy.stored(in: userDefaults)
    }

    func setVideoCodecPreference(_ preference: VideoCodecPreference) {
        let resolvedPreference = preference.resolvedForCurrentDevice
        guard videoCodecPreference != resolvedPreference
            || userDefaults.string(forKey: VideoCodecPreference.storageKey) != resolvedPreference.rawValue
        else { return }
        videoCodecPreference = resolvedPreference
        userDefaults.set(resolvedPreference.rawValue, forKey: VideoCodecPreference.storageKey)
    }

    func setForceHardwareDecodeEnabled(_ isEnabled: Bool) {
        guard forceHardwareDecodeEnabled != isEnabled
            || PlaybackHardwareDecodePolicy.stored(in: userDefaults) != isEnabled
        else { return }
        forceHardwareDecodeEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: PlaybackHardwareDecodePolicy.storageKey)
    }

    func setDolbyVisionRenderingPolicy(_ policy: DolbyVisionRenderingPolicy) {
        guard dolbyVisionRenderingPolicy != policy
            || DolbyVisionRenderingPolicy.stored(in: userDefaults) != policy
        else { return }
        dolbyVisionRenderingPolicy = policy
        userDefaults.set(policy.rawValue, forKey: DolbyVisionRenderingPolicy.storageKey)
    }

    func reload() {
        videoCodecPreference = VideoCodecPreference.stored(in: userDefaults)
        forceHardwareDecodeEnabled = PlaybackHardwareDecodePolicy.stored(in: userDefaults)
        dolbyVisionRenderingPolicy = DolbyVisionRenderingPolicy.stored(in: userDefaults)
    }
}
