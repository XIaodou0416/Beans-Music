import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

