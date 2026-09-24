import Foundation
import SwiftUI

enum PlayerPerformanceOverlayFormatting {
    static var panelBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    static var sectionBackground: Color {
        Color(uiColor: .tertiarySystemBackground)
    }

    static var panelStroke: Color {
        Color(uiColor: .separator)
    }

    static func shortMetricsID(_ metricsID: String) -> String {
        guard metricsID.count > 8 else { return metricsID }
        return String(metricsID.suffix(8))
    }

    static func millisecondsText(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }

    static func metricColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        if value >= 2500 {
            return .red
        }
        if value >= 1400 {
            return .orange
        }
        return .green
    }

    static func counterColor(for session: PlayerPerformanceSession) -> Color {
        (session.bufferCount > 0
            || session.speedBoostInterruptionCount > 0
            || session.resumeRecoverySlowCount > 0
            || session.seekRecoverySlowCount > 0)
            ? .orange
            : .secondary
    }

    static func startupWaterfallBarWidth(milliseconds: Int, maxMilliseconds: Int) -> CGFloat {
        let ratio = CGFloat(milliseconds) / CGFloat(max(maxMilliseconds, 1))
        return max(4, min(70, ratio * 70))
    }

    static func prepareStageMetrics(from message: String) -> [PrepareStageMetric] {
        let metrics = message
            .split(separator: " ")
            .compactMap { token -> PrepareStageMetric? in
                let parts = token.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return PrepareStageMetric(
                    name: String(parts[0]),
                    value: String(parts[1])
                )
            }
        return metrics.isEmpty
            ? [PrepareStageMetric(name: "prepare", value: message)]
            : metrics
    }

    static func startupBreakdownMetrics(from message: String) -> [PrepareStageMetric] {
        let values = keyValueTokens(in: message)
        let preferredKeys = [
            "ksStartup",
            "firstFrame",
            "prepareToFrame",
            "playToFrame",
            "prepareToPlay",
            "ready",
            "renderAfterReady",
            "decodedFrame",
            "ksRender",
            "ffmpeg",
            "ffOpen",
            "ffFind",
            "ffReady",
            "endpoint",
            "layer",
            "layerCreate",
            "viewInstall",
            "ksLayer",
            "playerNew",
            "playerInit",
            "audioSession",
            "audioOut",
            "itemInit",
            "ffGlobal",
            "videoOut",
            "bindOut",
            "prepareCall",
            "codecCreate",
            "readVideo",
            "readAudio",
            "decodeVideo",
            "decodeAudio",
            "playable",
            "frameDecoded",
            "frameFetched",
            "displayEnq",
            "metalDrawable",
            "metalDraw",
            "decodeReady",
            "fetchGap",
            "enqueueGap",
            "metalWait",
            "probe",
            "endpointKind",
            "variants",
            "codec",
            "fps",
            "res",
            "time"
        ]
        return preferredKeys.compactMap { key in
            guard let value = values[key], !value.isEmpty else { return nil }
            return PrepareStageMetric(
                name: startupBreakdownDisplayName(for: key),
                value: value
            )
        }
    }

    static func millisecondsValue(from text: String) -> Int? {
        if text.hasSuffix("ms") {
            return Int(text.dropLast(2))
        }
        if text.hasSuffix("s"),
           let seconds = Double(text.dropLast()) {
            return Int((seconds * 1_000).rounded())
        }
        return nil
    }

    static func startupSampleSummaries(
        from samples: [PlayerStartupPerformanceSample]
    ) -> [StartupSampleMetricSummary] {
        [
            summary(id: "player", title: "播放器", samples: samples, value: \.firstFramePlayerMilliseconds),
            summary(id: "ready", title: "ready", samples: samples, value: \.readyMilliseconds),
            summary(id: "ffmpeg", title: "ffmpeg", samples: samples, value: \.ffmpegMilliseconds),
            summary(id: "ffOpen", title: "open", samples: samples, value: \.ffmpegOpenMilliseconds),
            summary(id: "ffFind", title: "find", samples: samples, value: \.ffmpegFindMilliseconds),
            summary(id: "ffReady", title: "ffReady", samples: samples, value: \.ffmpegReadyMilliseconds),
            summary(id: "render", title: "render", samples: samples, value: \.renderMilliseconds),
            summary(id: "layer", title: "layer", samples: samples, value: \.layerMilliseconds),
            summary(id: "endpoint", title: "endpoint", samples: samples, value: \.endpointMilliseconds),
            summary(id: "frameDone", title: "frame", samples: samples, value: \.frameDecodedMilliseconds),
            summary(id: "fetch", title: "fetch", samples: samples, value: \.frameFetchedMilliseconds),
            summary(id: "enqueue", title: "enq", samples: samples, value: \.displayEnqueueMilliseconds)
        ].compactMap { $0 }
    }

    static func comparableStartupSamples(
        from samples: [PlayerStartupPerformanceSample]
    ) -> [PlayerStartupPerformanceSample] {
        guard let latest = samples.last else { return samples }
        return samples.filter { sample in
            sample.codec == latest.codec
                && sample.resolution == latest.resolution
                && sample.frameRate == latest.frameRate
                && sample.probe == latest.probe
        }
    }

    static func stableStartupSamples(
        from samples: [PlayerStartupPerformanceSample]
    ) -> [PlayerStartupPerformanceSample] {
        let comparableSamples = comparableStartupSamples(from: samples)
        guard comparableSamples.count >= 3 else { return comparableSamples }

        let playerLimit = outlierLimit(
            for: comparableSamples.compactMap(\.firstFramePlayerMilliseconds),
            minimumHeadroom: 180,
            multiplier: 2
        )
        let readyLimit = outlierLimit(
            for: comparableSamples.compactMap(\.readyMilliseconds),
            minimumHeadroom: 180,
            multiplier: 2
        )
        let ffmpegLimit = outlierLimit(
            for: comparableSamples.compactMap(\.ffmpegMilliseconds),
            minimumHeadroom: 180,
            multiplier: 3
        )

        let stableSamples = comparableSamples.filter { sample in
            !isAboveOutlierLimit(sample.firstFramePlayerMilliseconds, limit: playerLimit)
                && !isAboveOutlierLimit(sample.readyMilliseconds, limit: readyLimit)
                && !isAboveOutlierLimit(sample.ffmpegMilliseconds, limit: ffmpegLimit)
        }

        return stableSamples.count >= 2 ? stableSamples : comparableSamples
    }

    static func startupSampleFilterText(
        for samples: [PlayerStartupPerformanceSample]
    ) -> String? {
        guard let latest = samples.last else { return nil }
        let codec = latest.codec ?? "-"
        let resolution = latest.resolution ?? "-"
        let frameRate = latest.frameRate.map { "\($0)fps" } ?? "-"
        let probe = latest.probe ?? "-"
        return "\(codec) \(resolution) \(frameRate) \(probe)"
    }

    @MainActor
    static func performanceCopyText(
        metricsID: String,
        session: PlayerPerformanceSession?,
        diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore,
        playerViewModel: PlayerStateViewModel?,
        experimentSnapshot: VideoDetailPerformanceExperimentSnapshot = VideoDetailPerformanceExperimentSnapshot()
    ) -> String {
        PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.text(
            metricsID: metricsID,
            session: session,
            diagnosticsStore: diagnosticsStore,
            playerViewModel: playerViewModel,
            experimentSnapshot: experimentSnapshot
        )
    }

    private static func keyValueTokens(in message: String) -> [String: String] {
        var tokens: [String: String] = [:]
        for token in message.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            tokens[String(parts[0])] = String(parts[1])
        }
        return tokens
    }

    private static func startupBreakdownDisplayName(for key: String) -> String {
        switch key {
        case "ksStartup": return "stage"
        case "renderAfterReady": return "render"
        case "decodedFrame": return "decoded"
        case "ksRender": return "ksRender"
        case "ffOpen": return "open"
        case "ffFind": return "find"
        case "ffReady": return "ffReady"
        case "layerCreate": return "layerNew"
        case "viewInstall": return "viewAdd"
        case "ksLayer": return "ksLayer"
        case "playerNew": return "playerNew"
        case "playerInit": return "playerInit"
        case "audioSession": return "audioSession"
        case "audioOut": return "audioOut"
        case "itemInit": return "itemInit"
        case "ffGlobal": return "ffGlobal"
        case "videoOut": return "videoOut"
        case "bindOut": return "bindOut"
        case "codecCreate": return "codec"
        case "readVideo": return "readV"
        case "readAudio": return "readA"
        case "decodeVideo": return "decodeV"
        case "decodeAudio": return "decodeA"
        case "frameDecoded": return "frameDone"
        case "frameFetched": return "fetch"
        case "displayEnq": return "enq"
        case "metalDrawable": return "drawable"
        case "metalDraw": return "metalDraw"
        case "decodeReady": return "decodeDone"
        case "fetchGap": return "done>fetch"
        case "enqueueGap": return "fetch>enq"
        case "metalWait": return "metalWait"
        case "prepareCall": return "prepare"
        case "prepareToPlay": return "prepare>play"
        case "playToFrame": return "play>frame"
        case "prepareToFrame": return "prepare>frame"
        case "endpointKind": return "endpointType"
        default: return key
        }
    }

    private static var copyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private static func latestSampleValue(
        _ samples: [PlayerStartupPerformanceSample],
        _ keyPath: KeyPath<PlayerStartupPerformanceSample, String?>
    ) -> String? {
        samples.last?[keyPath: keyPath]
    }

    private static func outlierLimit(
        for values: [Int],
        minimumHeadroom: Int,
        multiplier: Double
    ) -> Int? {
        guard let median = medianValue(for: values) else { return nil }
        let multipliedLimit = Int((Double(median) * multiplier).rounded())
        return max(multipliedLimit, median + minimumHeadroom)
    }

    private static func medianValue(for values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sortedValues = values.sorted()
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return Int((Double(sortedValues[middle - 1] + sortedValues[middle]) / 2).rounded())
        }
        return sortedValues[middle]
    }

    private static func isAboveOutlierLimit(_ value: Int?, limit: Int?) -> Bool {
        guard let value, let limit else { return false }
        return value > limit
    }

    private static func summary(
        id: String,
        title: String,
        samples: [PlayerStartupPerformanceSample],
        value: KeyPath<PlayerStartupPerformanceSample, Int?>
    ) -> StartupSampleMetricSummary? {
        let values = samples.compactMap { $0[keyPath: value] }
        guard !values.isEmpty else { return nil }
        let average = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return StartupSampleMetricSummary(
            id: id,
            title: title,
            minimumMilliseconds: values.min() ?? average,
            averageMilliseconds: average,
            maximumMilliseconds: values.max() ?? average
        )
    }
}
