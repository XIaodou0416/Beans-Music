import Foundation

@MainActor
extension PlaybackNetworkDiagnosticsTextBuilder {
    func appendOptional(_ title: String, _ value: String?, to lines: inout [String]) {
        guard let value, !value.isEmpty else { return }
        lines.append("\(title)：\(value)")
    }
}
