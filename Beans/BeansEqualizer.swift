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
    case jazz
    case electronic
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
        case .jazz: return beansLocalized("爵士", "Jazz")
        case .electronic: return beansLocalized("电子", "Electronic")
        case .custom: return beansLocalized("自定义", "Custom")
        }
    }

    var gains: [Double]? {
        switch self {
        case .flat: return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bass: return [6, 5, 3, 1, 0, 0, -1, -1, 0, 0]
        case .vocal: return [-2, -1, 0, 2, 4, 4, 3, 2, 0, -1]
        case .pop: return [2, 2, 1, 0, 2, 3, 2, 1, 2, 2]
        case .rock: return [5, 4, 2, -1, -2, 1, 3, 4, 5, 4]
        case .classical: return [3, 2, 1, 0, 0, 1, 2, 3, 4, 4]
        case .jazz: return [3, 2, 1, 2, -1, -1, 0, 2, 3, 3]
        case .electronic: return [5, 4, 1, -2, -1, 2, 4, 3, 5, 4]
        case .custom: return nil
        }
    }
}

struct BeansEqualizerCustomPreset: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var gains: [Double]
    var preampGain: Double

    init(id: String = UUID().uuidString, name: String, gains: [Double], preampGain: Double) {
        self.id = id
        self.name = name
        self.gains = gains
        self.preampGain = preampGain
    }
}

/// AVPlayerItem uses an audio-processing tap for the equalizer, so it keeps the
/// existing AVPlayer playback, queue, remote command, and background behavior.
final class BeansEqualizer: ObservableObject {
    static let shared = BeansEqualizer()
    static let settingsDidChange = Notification.Name("beans.equalizer.settingsDidChange")

    static let bandFrequencies: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let maximumGain: Double = 12

    @Published private(set) var isEnabled: Bool
    @Published private(set) var bandGains: [Double]
    @Published private(set) var selectedPreset: BeansEqualizerPreset
    @Published private(set) var selectedCustomPresetName: String?
    @Published private(set) var preampGain: Double
    @Published private(set) var customPresets: [BeansEqualizerCustomPreset]

    private let defaults = UserDefaults.standard
    private let configurationLock = NSLock()
    private var processingEnabled = false
    private var processingGains: [Double] = Array(repeating: 0, count: 10)
    private var processingPreampLinear: Float = 1
    private var processingFormatIsFloat32 = false
    private var sampleRate: Double = 44_100
    private var coefficients: [BiquadCoefficients] = Array(repeating: .identity, count: 10)
    private var filterStates: [BiquadState] = Array(repeating: .zero, count: 80)
    private var pendingPersistWorkItem: DispatchWorkItem?

    private static let enabledKey = "beans.equalizer.enabled"
    private static let gainsKey = "beans.equalizer.bandGains"
    private static let presetKey = "beans.equalizer.preset"
    private static let customPresetNameKey = "beans.equalizer.customPresetName"
    private static let customPresetsKey = "beans.equalizer.customPresets"
    private static let preampKey = "beans.equalizer.preampGain"
    private static let maximumChannels = 8

    private init() {
        let storedGains = defaults.array(forKey: Self.gainsKey)?
            .compactMap { ($0 as? NSNumber)?.doubleValue }
        let normalizedGains = Self.normalizedGains(storedGains)
        let storedPreset = defaults.string(forKey: Self.presetKey)
            .flatMap(BeansEqualizerPreset.init(rawValue:)) ?? .flat
        let storedCustomPresets = defaults.data(forKey: Self.customPresetsKey)
            .flatMap { try? JSONDecoder().decode([BeansEqualizerCustomPreset].self, from: $0) } ?? []
        let normalizedCustomPresets = storedCustomPresets.compactMap { preset -> BeansEqualizerCustomPreset? in
            let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return BeansEqualizerCustomPreset(
                id: preset.id,
                name: name,
                gains: Self.normalizedGains(preset.gains),
                preampGain: Self.normalizedGain(preset.preampGain)
            )
        }

        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        bandGains = normalizedGains
        selectedPreset = storedPreset
        selectedCustomPresetName = defaults.string(forKey: Self.customPresetNameKey)
        preampGain = Self.normalizedGain((defaults.object(forKey: Self.preampKey) as? NSNumber)?.doubleValue ?? 0)
        customPresets = normalizedCustomPresets
        processingEnabled = isEnabled
        processingGains = normalizedGains
        processingPreampLinear = Self.linearGain(for: preampGain)
        rebuildCoefficientsLocked(using: normalizedGains)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        configurationLock.lock()
        processingEnabled = enabled
        configurationLock.unlock()
        defaults.set(enabled, forKey: Self.enabledKey)
        notifySettingsChanged()
    }

    func setBandGain(at index: Int, to gain: Double) {
        guard bandGains.indices.contains(index) else { return }
        let normalized = Self.normalizedGain(gain)
        guard bandGains[index] != normalized else { return }
        var updatedGains = bandGains
        updatedGains[index] = normalized
        bandGains = updatedGains
        selectedPreset = .custom
        selectedCustomPresetName = nil
        configurationLock.lock()
        processingGains = updatedGains
        rebuildCoefficientsLocked(using: updatedGains)
        configurationLock.unlock()
        schedulePersist()
        notifySettingsChanged()
    }

    func setPreampGain(_ gain: Double) {
        let normalized = Self.normalizedGain(gain)
        guard preampGain != normalized else { return }
        preampGain = normalized
        selectedPreset = .custom
        selectedCustomPresetName = nil
        configurationLock.lock()
        processingPreampLinear = Self.linearGain(for: normalized)
        configurationLock.unlock()
        schedulePersist()
        notifySettingsChanged()
    }

    func applyPreset(_ preset: BeansEqualizerPreset) {
        guard let gains = preset.gains else { return }
        let normalized = Self.normalizedGains(gains)
        bandGains = normalized
        selectedPreset = preset
        selectedCustomPresetName = nil
        preampGain = 0
        configurationLock.lock()
        processingGains = normalized
        processingPreampLinear = 1
        rebuildCoefficientsLocked(using: normalized)
        configurationLock.unlock()
        persistNow()
        notifySettingsChanged()
    }

    func applyCustomPreset(_ preset: BeansEqualizerCustomPreset) {
        let normalized = Self.normalizedGains(preset.gains)
        let normalizedPreamp = Self.normalizedGain(preset.preampGain)
        bandGains = normalized
        selectedPreset = .custom
        selectedCustomPresetName = preset.name
        preampGain = normalizedPreamp
        configurationLock.lock()
        processingGains = normalized
        processingPreampLinear = Self.linearGain(for: normalizedPreamp)
        rebuildCoefficientsLocked(using: normalized)
        configurationLock.unlock()
        persistNow()
        notifySettingsChanged()
    }

    @discardableResult
    func saveCustomPreset(name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        let current = BeansEqualizerCustomPreset(
            name: trimmedName,
            gains: bandGains,
            preampGain: preampGain
        )
        if let index = customPresets.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            customPresets[index] = BeansEqualizerCustomPreset(
                id: customPresets[index].id,
                name: trimmedName,
                gains: current.gains,
                preampGain: current.preampGain
            )
        } else {
            customPresets.append(current)
        }
        selectedPreset = .custom
        selectedCustomPresetName = trimmedName
        persistNow()
        return true
    }

    func deleteCustomPreset(_ preset: BeansEqualizerCustomPreset) {
        customPresets.removeAll { $0.id == preset.id }
        if selectedCustomPresetName == preset.name {
            selectedCustomPresetName = nil
        }
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
            init: equalizerTapInit,
            finalize: equalizerTapFinalize,
            prepare: equalizerTapPrepare,
            unprepare: equalizerTapUnprepare,
            process: equalizerTapProcess
        )
        var tap: MTAudioProcessingTap?
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
        parameters.audioTapProcessor = tap
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
        if let selectedCustomPresetName {
            defaults.set(selectedCustomPresetName, forKey: Self.customPresetNameKey)
        } else {
            defaults.removeObject(forKey: Self.customPresetNameKey)
        }
        defaults.set(preampGain, forKey: Self.preampKey)
        if let data = try? JSONEncoder().encode(customPresets) {
            defaults.set(data, forKey: Self.customPresetsKey)
        }
    }

    private static func normalizedGains(_ values: [Double]?) -> [Double] {
        let values = values ?? []
        if values.count == 5 {
            // Migrate the original five-band layout to the nearest bands in the
            // new ten-band studio layout without discarding user adjustments.
            let legacyIndexes = [0, 2, 4, 7, 9]
            var migrated = Array(repeating: 0.0, count: bandFrequencies.count)
            for (legacyIndex, newIndex) in legacyIndexes.enumerated() where legacyIndex < values.count {
                migrated[newIndex] = values[legacyIndex]
            }
            return migrated.map(normalizedGain)
        }
        return bandFrequencies.indices.map { index in
            normalizedGain(index < values.count ? values[index] : 0)
        }
    }

    private static func normalizedGain(_ value: Double) -> Double {
        let clamped = min(max(value, -maximumGain), maximumGain)
        return (clamped * 2).rounded() / 2
    }

    private static func linearGain(for gain: Double) -> Float {
        Float(pow(10, gain / 20))
    }

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: Self.settingsDidChange, object: self)
    }

    private func rebuildCoefficientsLocked(using gains: [Double]) {
        coefficients = zip(Self.bandFrequencies, Self.normalizedGains(gains)).map { frequency, gain in
            BiquadCoefficients.peaking(frequency: frequency, gain: gain, sampleRate: sampleRate)
        }
    }

    fileprivate func prepare(with format: AudioStreamBasicDescription) {
        configurationLock.lock()
        sampleRate = max(format.mSampleRate, 8_000)
        processingFormatIsFloat32 = format.mFormatID == kAudioFormatLinearPCM
            && format.mBitsPerChannel == 32
            && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        filterStates = Array(repeating: .zero, count: Self.maximumChannels * Self.bandFrequencies.count)
        rebuildCoefficientsLocked(using: processingGains)
        configurationLock.unlock()
    }

    fileprivate func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
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
                    var sample = samples[sampleIndex] * processingPreampLinear
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

}

private func equalizerTapInit(
    _ tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func equalizerTapFinalize(_ tap: MTAudioProcessingTap) {}

private func equalizerTapPrepare(
    _ tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let equalizer = Unmanaged<BeansEqualizer>.fromOpaque(storage).takeUnretainedValue()
    equalizer.prepare(with: processingFormat.pointee)
}

private func equalizerTapUnprepare(_ tap: MTAudioProcessingTap) {}

private func equalizerTapProcess(
    _ tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let _ = flags
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
    let storage = MTAudioProcessingTapGetStorage(tap)
    let equalizer = Unmanaged<BeansEqualizer>.fromOpaque(storage).takeUnretainedValue()
    equalizer.process(bufferList: bufferListInOut, frameCount: Int(sourceFrames))
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
