import SwiftUI
import UIKit

enum AppThemeTintColor {
    nonisolated static let defaultHex = "#FB7299"
    nonisolated static let previousDefaultHex = "#EE719E"
    nonisolated static let legacyDefaultHexes = ["#007AFF", "#FF2D55"]
    nonisolated static let toneHexes = [
        "#FB7299", "#FF2D55", "#AF52DE", "#5856D6",
        "#007AFF", "#5AC8FA", "#34C759", "#FF9500"
    ]

    static func normalizedHex(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6,
              trimmed.allSatisfy(\.isHexDigit)
        else { return nil }
        return "#\(trimmed.uppercased())"
    }

    static func color(for hex: String) -> Color {
        Color(hexRGB: normalizedHex(hex) ?? defaultHex) ?? .pink
    }

    static func uiColor(for hex: String) -> UIColor {
        UIColor(Color(hexRGB: normalizedHex(hex) ?? defaultHex) ?? .pink)
    }

    static func hexString(from color: Color) -> String? {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}

extension Color {
    init?(hexRGB: String) {
        guard let normalized = AppThemeTintColor.normalizedHex(hexRGB) else { return nil }
        let hex = String(normalized.dropFirst())
        guard let value = Int(hex, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

private struct AppThemeTintColorKey: EnvironmentKey {
    static let defaultValue: Color = AppThemeTintColor.color(for: AppThemeTintColor.defaultHex)
}

extension EnvironmentValues {
    var appThemeTintColor: Color {
        get { self[AppThemeTintColorKey.self] }
        set { self[AppThemeTintColorKey.self] = newValue }
    }
}
