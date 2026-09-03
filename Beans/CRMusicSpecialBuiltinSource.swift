import Foundation

enum CRMusicSpecialBuiltinSource {
    static let script: String = {
        guard let url = Bundle.main.url(forResource: "CRMusicSpecialBuiltinSource", withExtension: "js"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return value
    }()
}
