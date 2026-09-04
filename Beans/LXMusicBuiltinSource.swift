import Foundation

enum LXMusicBuiltinSource {
    static let script: String = {
        guard let url = Bundle.main.url(forResource: "LXMusicBuiltinSource", withExtension: "js"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return value
    }()
}
