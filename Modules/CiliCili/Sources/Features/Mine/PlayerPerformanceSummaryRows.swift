import SwiftUI

enum PlayerPerformanceMetricText {
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
}
