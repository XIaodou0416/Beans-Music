import Foundation

struct PrepareStageMetric: Hashable {
    let name: String
    let value: String

    var milliseconds: Int? {
        let numericText = value
            .replacingOccurrences(of: "ms", with: "")
            .replacingOccurrences(of: "s", with: "")
        guard let number = Double(numericText) else { return nil }
        return value.hasSuffix("s")
            ? Int((number * 1000).rounded())
            : Int(number.rounded())
    }
}

struct StartupWaterfallStage: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date

    var milliseconds: Int {
        max(Int((end.timeIntervalSince(start) * 1000).rounded()), 0)
    }
}

struct StartupSampleMetricSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let minimumMilliseconds: Int
    let averageMilliseconds: Int
    let maximumMilliseconds: Int
}
