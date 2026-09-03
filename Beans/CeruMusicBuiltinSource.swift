import Foundation

enum CeruMusicBuiltinSource {
    static let script: String = {
        guard let url = Bundle.main.url(forResource: "CeruMusicBuiltinSource", withExtension: "js"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return value
    }()
}
