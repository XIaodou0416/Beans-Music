import Foundation
import QuartzCore

extension VideoDetailViewModel {
    func elapsedMilliseconds(since startTime: CFTimeInterval?) -> Int? {
        guard let startTime else { return nil }
        return Int(((CACurrentMediaTime() - startTime) * 1000).rounded())
    }

    func elapsedMilliseconds(since startTime: CFTimeInterval) -> Int {
        Int(((CACurrentMediaTime() - startTime) * 1000).rounded())
    }

    func formattedMilliseconds(_ value: Int?) -> String {
        guard let value else { return "n/a" }
        return formatMilliseconds(value)
    }

    func formatMilliseconds(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }
}
