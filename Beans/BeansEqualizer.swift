import AVFoundation
import Combine
import Foundation
import MediaToolbox

enum BeansEqualizerPreset: String, CaseIterable, Identifiable {
    case flat
    case bass
    case vocal
    case pop
    case rock
    case classical
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flat: return beansLocalized("默认", "Default")
        case .bass: return beansLocalized("低音增强", "Bass Boost")
        case .vocal: return beansLocalized("人声", "Vocal")
        case .pop: return beansLocalized("流行", "Pop")
        case .rock: return beansLocalized("摇滚", "Rock")
        case .classical: return beansLocalized("古典", "Classical")
        case .custom: return beansLocalized("自定义", "Custom")
        }
    }

    var gains: [Double]? {
        switch self {
        case .flat: return [0, 0, 0, 0, 0]
        case .bass: return [5, 3, 0, -1, 0]
        case .vocal: return [-1, 0, 3, 2, -1]
        case .pop: return [2, 1, 3, 1, 2]
        case .rock: return [4, 2, -1, 2, 4]
        case .classical: return [2, 1, 0, 2, 3]
        case .custom: return nil
        }
    }
}

/// AVPlayerItem uses an audio-processing tap for the equalizer, so it keeps the
/// existing AVPlayer playback, queue, remote command, and background behavior.
final class BeansEqualizer: ObservableObject {
    static let shared = BeansEqualizer()
    static let settingsDidChange = Notification.Name("beans.equalizer.settingsDidChange")

    static let bandFrequencies: [Double] = [60, 230, 910, 3_600, 14_000]
    static let maximumGain: Double = 12

    @Published private(set) var isEnabled: Bool
    @Published private(set) var bandGains: [Double]
    @Published private(set) var selectedPreset: BeansEqualizerPreset

    private let defaults = UserDefaults.standard
    private let configurationLock = NSLock()
    private var processingEnabled = false
    private var processingGains: [Double] = [0, 0, 0, 0, 0]
    private var processingFormatIsFloat32 = false
    private var sampleRate: Double = 44_100
    private var coefficients: [BiquadCoefficients] = Array(repeating: .identity, count: 5)
    private var filterStates: [BiquadState] = Array(repeating: .zero, count: 40)
    private var pendingPersistWorkItem: DispatchWorkItem?

    private static let enabledKey = "beans.equalizer.enabled"
    private static let gainsKey = "beans.equalizer.bandGains"
    private static let presetKey = "beans.equalizer.preset"
    private static let maximumChannels = 8

    private init() {
        let storedGains = defaults.array(forKey: Self.gainsKey)?
            .compactMap { ($0 as? NSNumber)?.doubleValue }
        let normalizedGains = Self.normalizedGains(storedGains)
        let storedPreset = defaults.string(forKey: Self.presetKey)
            .flatMap(BeansEqualizerPreset.init(rawValue:)) ?? .flat

        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        bandGains = normalizedGains
        selectedPreset = storedPreset
        processingEnabled = isEnabled
        processingGains = normalizedGains
        rebuildCoefficientsLocked(using: normalizedGains)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        configurationLock.lock()
        processingEnabled = enabled
        configurationLock.unlock()
        defaults.set(enabled, forKey: Self.enabledKey)
        NotificationCenter.default.post(name: Self.settingsDidChange, object: self)
    }

    func setBandGain(at index: Int, to gain: Double) {
        guard bandGains.indices.contains(index) else { return }
        let normalized = Self.normalizedGain(gain)
        guard bandGains[index] != normalized || selectedPreset != .custom else { return }
        var updatedGains = bandGains
        updatedGains[index] = normalized
        bandGains = updatedGains
        selectedPreset = .custom
        configurationLock.lock()
        processingGains = updatedGains
        rebuildCoefficientsLocked(using: updatedGains)
        configurationLock.unlock()
        schedulePersist()
    }

    func applyPreset(_ preset: BeansEqualizerPreset) {
        guard let gains = preset.gains else { return }
        let normalized = Self.normalizedGains(gains)
        bandGains = normalized
        selectedPreset = preset
        configurationLock.lock()
        processingGains = normalized
        rebuildCoefficientsLocked(using: normalized)
        configurationLock.unlock()
        persistNow()
    }

    func reset() {
        applyPreset(.flat)
    }

    /// Creates one processing tap per AVPlayerItem. The singleton stays alive for
    /// the whole app lifetime, so the tap's unretained callback context is stable.
    func makeAudioMix(for track: AVAssetTrack) -> AVAudioMix? {
        configurationLock.lock()
        let shouldProcess = processingEnabled
        configurationLock.unlock()
        guard shouldProcess else { return nil }

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: Self.tapInit,
            finalize: Self.tapFinalize,
            prepare: Self.tapPrepare,
            unprepare: Self.tapUnprepare,
            process: Self.tapProcess
        )
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let tap else {
            BeansLogger.shared.log("均衡器音频处理器创建失败：\(status)", level: .error)
            return nil
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap.takeRetainedValue()
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    private func schedulePersist() {
        pendingPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistNow()
        }
        pendingPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func persistNow() {
        pendingPersistWorkItem?.cancel()
        pendingPersistWorkItem = nil
        defaults.set(bandGains, forKey: Self.gainsKey)
        defaults.set(selectedPreset.rawValue, forKey: Self.presetKey)
    }

    private static func normalizedGains(_ values: [Double]?) -> [Double] {
        let values = values ?? []
        return bandFrequencies.indices.map { index in
            normalizedGain(index < values.count ? values[index] : 0)
        }
    }

    private static func normalizedGain(_ value: Double) -> Double {
        let clamped = min(max(value, -maximumGain), maximumGain)
        return (clamped * 2).rounded() / 2
    }

    private func rebuildCoefficientsLocked(using gains: [Double]) {
        coefficients = zip(Self.bandFrequencies, Self.normalizedGains(gains)).map { frequency, gain in
            BiquadCoefficients.peaking(frequency: frequency, gain: gain, sampleRate: sampleRate)
        }
    }

    private func prepare(with format: AudioStreamBasicDescription) {
        configurationLock.lock()
        sampleRate = max(format.mSampleRate, 8_000)
        processingFormatIsFloat32 = format.mFormatID == kAudioFormatLinearPCM
            && format.mBitsPerChannel == 32
            && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        filterStates = Array(repeating: .zero, count: Self.maximumChannels * Self.bandFrequencies.count)
        rebuildCoefficientsLocked(using: processingGains)
        configurationLock.unlock()
    }

    private func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }
        configurationLock.lock()
        defer { configurationLock.unlock() }
        guard processingEnabled, processingFormatIsFloat32 else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        var firstChannelIndex = 0
        for buffer in buffers {
            let channelCount = max(Int(buffer.mNumberChannels), 1)
            defer { firstChannelIndex += channelCount }
            guard let rawData = buffer.mData else { continue }

            let samples = rawData.assumingMemoryBound(to: Float.self)
            let availableFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channelCount)
            let framesToProcess = min(frameCount, availableFrames)
            guard framesToProcess > 0 else { continue }

            for channelOffset in 0..<channelCount {
                let channel = min(firstChannelIndex + channelOffset, Self.maximumChannels - 1)
                let stateOffset = channel * Self.bandFrequencies.count
                for frame in 0..<framesToProcess {
                    let sampleIndex = frame * channelCount + channelOffset
                    var sample = samples[sampleIndex]
                    for bandIndex in coefficients.indices {
                        let stateIndex = stateOffset + bandIndex
                        let coefficient = coefficients[bandIndex]
                        var state = filterStates[stateIndex]
                        let filtered = coefficient.b0 * sample + state.z1
                        state.z1 = coefficient.b1 * sample - coefficient.a1 * filtered + state.z2
                        state.z2 = coefficient.b2 * sample - coefficient.a2 * filtered
                        filterStates[stateIndex] = state
                        sample = filtered
                    }
                    samples[sampleIndex] = sample.isFinite ? min(max(sample, -4), 4) : 0
                }
            }
        }
    }

    private static func tapInit(
        _ tap: MTAudioProcessingTap,
        clientInfo: UnsafeMutableRawPointer?,
        tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
    ) {
        tapStorageOut.pointee = clientInfo
    }

    private static func tapFinalize(_ tap: MTAudioProcessingTap) {}

    private static func tapPrepare(
        _ tap: MTAudioProcessingTap,
        maxFrames: CMItemCount,
        processingFormat: UnsafePointer<AudioStreamBasicDescription>
    ) {
        guard let storage = MTAudioProcessingTapGetStorage(tap) else { return }
        let equalizer = Unmanaged<BeansEqualizer>.fromOpaque(storage).takeUnretainedValue()
        equalizer.prepare(with: processingFormat.pointee)
    }

    private static func tapUnprepare(_ tap: MTAudioProcessingTap) {}

    private static func tapProcess(
        _ tap: MTAudioProcessingTap,
        numberFrames: CMItemCount,
        flags: MTAudioProcessingTapFlags,
        bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
        numberFramesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
    ) {
        var sourceFlags = MTAudioProcessingTapFlags()
        var sourceFrames: CMItemCount = 0
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferListInOut,
            &sourceFlags,
            nil,
            &sourceFrames
        )
        guard status == noErr else {
            numberFramesOut.pointee = 0
            flagsOut.pointee = sourceFlags
            return
        }

        numberFramesOut.pointee = sourceFrames
        flagsOut.pointee = sourceFlags
        guard let storage = MTAudioProcessingTapGetStorage(tap) else { return }
        let equalizer = Unmanaged<BeansEqualizer>.fromOpaque(storage).takeUnretainedValue()
        equalizer.process(bufferList: bufferListInOut, frameCount: Int(sourceFrames))
    }
}

private struct BiquadCoefficients {
    let b0: Float
    let b1: Float
    let b2: Float
    let a1: Float
    let a2: Float

    static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    static func peaking(frequency: Double, gain: Double, sampleRate: Double) -> BiquadCoefficients {
        guard abs(gain) > 0.001 else { return .identity }
        let clampedFrequency = min(max(frequency, 20), sampleRate * 0.45)
        let amplitude = pow(10, gain / 40)
        let omega = 2 * Double.pi * clampedFrequency / sampleRate
        let alpha = sin(omega) / 2
        let cosine = cos(omega)
        let b0 = 1 + alpha * amplitude
        let b1 = -2 * cosine
        let b2 = 1 - alpha * amplitude
        let a0 = 1 + alpha / amplitude
        let a1 = -2 * cosine
        let a2 = 1 - alpha / amplitude
        return BiquadCoefficients(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }
}

private struct BiquadState {
    var z1: Float = 0
    var z2: Float = 0

    static let zero = BiquadState()
}
