import Combine
import QuartzCore
import UIKit

struct VideoRotationFrameReport: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let metricsID: String
    let title: String?
    let message: String

    var copyText: String {
        [
            "CiliCili 旋转帧报告",
            "generated: \(Self.dateFormatter.string(from: date))",
            "metricsID: \(metricsID)",
            "title: \(title ?? "-")",
            message
        ].joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

@MainActor
final class VideoRotationFrameReportStore: ObservableObject {
    static let shared = VideoRotationFrameReportStore()

    @Published private(set) var latestReport: VideoRotationFrameReport?

    private init() {}

    func record(metricsID: String, title: String?, message: String) {
        latestReport = VideoRotationFrameReport(
            date: Date(),
            metricsID: metricsID,
            title: title,
            message: message
        )
    }
}

@MainActor
final class VideoRotationFrameProbe: NSObject {
    private struct Sample {
        let elapsedMilliseconds: Double
        let frameMilliseconds: Double
    }

    private struct ProbeEvent {
        let elapsedMilliseconds: Double
        let message: String
    }

    private var displayLink: CADisplayLink?
    private var finishTask: Task<Void, Never>?
    private var metricsID: String?
    private var title: String?
    private var startTimestamp: CFTimeInterval = 0
    private var previousFrameTimestamp: CFTimeInterval?
    private var samples = [Sample]()
    private var events = [ProbeEvent]()

    private var isRecording: Bool {
        displayLink != nil
    }

    func start(
        metricsID: String,
        title: String?,
        mode: String,
        generation: Int,
        toLandscape: Bool,
        coordinatorSummary: String,
        maximumFrameRate: Int
    ) {
        finishTask?.cancel()
        if isRecording {
            mark("结束 reason=被新的旋转打断")
            stopAndRecordReport()
        }

        self.metricsID = metricsID
        self.title = title
        startTimestamp = CACurrentMediaTime()
        previousFrameTimestamp = nil
        samples.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
        mark(
            [
                "开始",
                "mode=\(mode)",
                "generation=\(generation)",
                "to=\(toLandscape ? "横屏" : "竖屏")",
                coordinatorSummary
            ].joined(separator: " ")
        )

        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        if #available(iOS 15.0, *) {
            let maximumFrameRate = Float(max(maximumFrameRate, 60))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: maximumFrameRate,
                preferred: maximumFrameRate
            )
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func mark(_ message: String) {
        guard startTimestamp > 0 else { return }
        let elapsed = (CACurrentMediaTime() - startTimestamp) * 1000
        events.append(ProbeEvent(elapsedMilliseconds: elapsed, message: message))
        if events.count > 24 {
            events.removeFirst(events.count - 24)
        }
    }

    func finish(reason: String, delayNanoseconds: UInt64 = 1_200_000_000) {
        guard isRecording else { return }
        mark("结束 reason=\(reason)")
        finishTask?.cancel()
        finishTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self, !Task.isCancelled else { return }
            self.stopAndRecordReport()
        }
    }

    func cancel() {
        finishTask?.cancel()
        finishTask = nil
        stopDisplayLink()
        reset()
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        defer { previousFrameTimestamp = link.timestamp }
        guard let previousFrameTimestamp else { return }
        let frameMilliseconds = max(0, (link.timestamp - previousFrameTimestamp) * 1000)
        let elapsedMilliseconds = max(0, (link.timestamp - startTimestamp) * 1000)
        samples.append(
            Sample(
                elapsedMilliseconds: elapsedMilliseconds,
                frameMilliseconds: frameMilliseconds
            )
        )
        if samples.count > 420 {
            samples.removeFirst(samples.count - 420)
        }
    }

    private func stopAndRecordReport() {
        stopDisplayLink()
        defer { reset() }
        guard let metricsID else { return }
        VideoRotationFrameReportStore.shared.record(
            metricsID: metricsID,
            title: title,
            message: reportMessage()
        )
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        finishTask = nil
    }

    private func reset() {
        metricsID = nil
        title = nil
        startTimestamp = 0
        previousFrameTimestamp = nil
        samples.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
    }

    private func reportMessage() -> String {
        guard !samples.isEmpty else {
            return "旋转帧报告 samples=0 events=\(eventSummary)"
        }

        let frameValues = samples.map(\.frameMilliseconds).sorted()
        let targetFrameRate = estimatedTargetFrameRate(from: frameValues)
        let budget = 1000 / Double(targetFrameRate)
        let dropCount = samples.reduce(0) { partial, sample in
            partial + max(0, Int((sample.frameMilliseconds / budget).rounded(.down)) - 1)
        }
        let overBudgetCount = samples.filter { $0.frameMilliseconds > budget * 1.2 }.count
        let severeCount = samples.filter { $0.frameMilliseconds >= budget * 2 }.count
        let hitchCount = samples.filter { $0.frameMilliseconds >= 50 }.count
        let duration = samples.last?.elapsedMilliseconds ?? 0

        return [
            "旋转帧报告",
            "duration=\(secondsText(duration))",
            "samples=\(samples.count)",
            "target=\(targetFrameRate)fps",
            "budget=\(millisecondsText(budget))",
            "avg=\(millisecondsText(average(frameValues)))",
            "p95=\(millisecondsText(percentile(0.95, in: frameValues)))",
            "p99=\(millisecondsText(percentile(0.99, in: frameValues)))",
            "max=\(millisecondsText(frameValues.last ?? 0))",
            "drop=\(dropCount)",
            "over=\(overBudgetCount)",
            "severe=\(severeCount)",
            "hitch=\(hitchCount)",
            "worst=\(worstFrameSummary(budget: budget))",
            "events=\(eventSummary)"
        ].joined(separator: " ")
    }

    private func worstFrameSummary(budget: Double) -> String {
        samples
            .sorted { $0.frameMilliseconds > $1.frameMilliseconds }
            .prefix(5)
            .map { sample in
                let droppedFrames = max(0, Int((sample.frameMilliseconds / budget).rounded(.down)) - 1)
                return [
                    "+\(secondsText(sample.elapsedMilliseconds))",
                    millisecondsText(sample.frameMilliseconds),
                    "drop=\(droppedFrames)",
                    "near=\(nearestEvent(to: sample.elapsedMilliseconds))"
                ].joined(separator: "/")
            }
            .joined(separator: ";")
    }

    private var eventSummary: String {
        events
            .suffix(8)
            .map { "+\(secondsText($0.elapsedMilliseconds)):\($0.message)" }
            .joined(separator: ";")
    }

    private func nearestEvent(to elapsedMilliseconds: Double) -> String {
        guard let event = events.min(by: {
            abs($0.elapsedMilliseconds - elapsedMilliseconds) < abs($1.elapsedMilliseconds - elapsedMilliseconds)
        }) else {
            return "-"
        }
        return event.message
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func percentile(_ percentile: Double, in values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let clamped = min(max(percentile, 0), 1)
        let index = Int((Double(values.count - 1) * clamped).rounded())
        return values[min(max(index, 0), values.count - 1)]
    }

    private func estimatedTargetFrameRate(from sortedFrameValues: [Double]) -> Int {
        let median = percentile(0.5, in: sortedFrameValues)
        return median <= 12 ? 120 : 60
    }

    private func millisecondsText(_ value: Double) -> String {
        String(format: "%.1fms", value)
    }

    private func secondsText(_ milliseconds: Double) -> String {
        String(format: "%.2fs", milliseconds / 1000)
    }
}
