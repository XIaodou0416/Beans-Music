import Foundation

enum QTMusicBuiltinSource {
    static let script: String = {
        guard let url = Bundle.main.url(forResource: "QTMusicBuiltinSource", withExtension: "js"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return value
    }()
}
