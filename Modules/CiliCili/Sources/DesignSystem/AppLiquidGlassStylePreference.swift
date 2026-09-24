import Foundation

enum AppLiquidGlassStylePreference: String, CaseIterable, Identifiable {
    case current

    static let storageKey = "cc.bili.display.liquidGlassStylePreference.v1"
    static let defaultValue: AppLiquidGlassStylePreference = .current

    var id: String { rawValue }

    init(storedRawValue: String?) {
        self = Self(rawValue: storedRawValue ?? "") ?? Self.defaultValue
    }

    var title: String {
        "这才叫液态玻璃"
    }

    var detail: String {
        "保留偏透明、轻着色和播放器清透玻璃效果。"
    }
}
