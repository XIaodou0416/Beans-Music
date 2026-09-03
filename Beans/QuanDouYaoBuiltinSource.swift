import Foundation

enum QuanDouYaoBuiltinSource {
    static let script: String = {
        guard let url = Bundle.main.url(forResource: "QuanDouYaoBuiltinSource", withExtension: "js"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return value
    }()
}
