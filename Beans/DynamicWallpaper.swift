import SwiftUI

/// Built-in animated wallpapers copied from ShipSwift's SwiftUI/Metal effects.
/// The renderers themselves are only available on iOS 17 and newer; older
/// systems keep using the existing static background implementation.
enum BeansDynamicWallpaperKind: String, CaseIterable, Identifiable {
    case off
    case fractalClouds
    case inkSmoke
    case liquidChrome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .fractalClouds: return "Fractal Clouds"
        case .inkSmoke: return "Ink Smoke"
        case .liquidChrome: return "Liquid Chrome"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "使用现有的颜色或图片壁纸"
        case .fractalClouds: return "分形云层，保留 ShipSwift 原始参数"
        case .inkSmoke: return "墨水扩散，保留 ShipSwift 原始参数"
        case .liquidChrome: return "液态金属，保留 ShipSwift 原始参数"
        }
    }

    var icon: String {
        switch self {
        case .off: return "nosign"
        case .fractalClouds: return "cloud.fog.fill"
        case .inkSmoke: return "drop.fill"
        case .liquidChrome: return "circle.lefthalf.filled"
        }
    }
}

final class DynamicWallpaperStore: ObservableObject {
    static let shared = DynamicWallpaperStore()

    @Published var kind: BeansDynamicWallpaperKind {
        didSet { save(kind.rawValue, forKey: Self.kindKey) }
    }

    // Fractal Clouds
    @Published var fractalSkyHex: String {
        didSet { save(fractalSkyHex, forKey: Self.fractalSkyKey) }
    }
    @Published var fractalCloudHex: String {
        didSet { save(fractalCloudHex, forKey: Self.fractalCloudKey) }
    }
    @Published var fractalWarmTintHex: String {
        didSet { save(fractalWarmTintHex, forKey: Self.fractalWarmTintKey) }
    }
    @Published var fractalWarmth: Double {
        didSet { save(fractalWarmth, forKey: Self.fractalWarmthKey) }
    }
    @Published var fractalSpeed: Double {
        didSet { save(fractalSpeed, forKey: Self.fractalSpeedKey) }
    }
    @Published var fractalZoom: Double {
        didSet { save(fractalZoom, forKey: Self.fractalZoomKey) }
    }
    @Published var fractalDriftX: Double {
        didSet { save(fractalDriftX, forKey: Self.fractalDriftXKey) }
    }
    @Published var fractalDriftY: Double {
        didSet { save(fractalDriftY, forKey: Self.fractalDriftYKey) }
    }
    @Published var fractalWarp: Double {
        didSet { save(fractalWarp, forKey: Self.fractalWarpKey) }
    }
    @Published var fractalCoverage: Double {
        didSet { save(fractalCoverage, forKey: Self.fractalCoverageKey) }
    }

    // Ink Smoke
    @Published var ink1Hex: String {
        didSet { save(ink1Hex, forKey: Self.ink1Key) }
    }
    @Published var ink2Hex: String {
        didSet { save(ink2Hex, forKey: Self.ink2Key) }
    }
    @Published var ink3Hex: String {
        didSet { save(ink3Hex, forKey: Self.ink3Key) }
    }
    @Published var ink4Hex: String {
        didSet { save(ink4Hex, forKey: Self.ink4Key) }
    }
    @Published var inkGlowHex: String {
        didSet { save(inkGlowHex, forKey: Self.inkGlowKey) }
    }
    @Published var inkSpeed: Double {
        didSet { save(inkSpeed, forKey: Self.inkSpeedKey) }
    }
    @Published var inkScale: Double {
        didSet { save(inkScale, forKey: Self.inkScaleKey) }
    }
    @Published var inkWarp: Double {
        didSet { save(inkWarp, forKey: Self.inkWarpKey) }
    }
    @Published var inkHighlight: Double {
        didSet { save(inkHighlight, forKey: Self.inkHighlightKey) }
    }

    // Liquid Chrome
    @Published var chromeShadowHex: String {
        didSet { save(chromeShadowHex, forKey: Self.chromeShadowKey) }
    }
    @Published var chromeSilverHex: String {
        didSet { save(chromeSilverHex, forKey: Self.chromeSilverKey) }
    }
    @Published var chromeHighlightHex: String {
        didSet { save(chromeHighlightHex, forKey: Self.chromeHighlightKey) }
    }
    @Published var chromeTintHex: String {
        didSet { save(chromeTintHex, forKey: Self.chromeTintKey) }
    }
    @Published var chromeSpeed: Double {
        didSet { save(chromeSpeed, forKey: Self.chromeSpeedKey) }
    }
    @Published var chromeScale: Double {
        didSet { save(chromeScale, forKey: Self.chromeScaleKey) }
    }
    @Published var chromeWarp: Double {
        didSet { save(chromeWarp, forKey: Self.chromeWarpKey) }
    }
    @Published var chromeContrast: Double {
        didSet { save(chromeContrast, forKey: Self.chromeContrastKey) }
    }
    @Published var chromeSpecPower: Double {
        didSet { save(chromeSpecPower, forKey: Self.chromeSpecPowerKey) }
    }
    @Published var chromeSpecStrength: Double {
        didSet { save(chromeSpecStrength, forKey: Self.chromeSpecStrengthKey) }
    }
    @Published var chromeTintStrength: Double {
        didSet { save(chromeTintStrength, forKey: Self.chromeTintStrengthKey) }
    }

    /// The renderer is intentionally unavailable below iOS 17. Do not create
    /// a custom shader fallback on older systems; the normal background stays.
    var renderableKind: BeansDynamicWallpaperKind {
        if #available(iOS 17.0, *) { return kind }
        return .off
    }

    private static let kindKey = "beans.dynamicWallpaper.kind"

    private static let fractalSkyKey = "beans.dynamicWallpaper.fractal.sky"
    private static let fractalCloudKey = "beans.dynamicWallpaper.fractal.cloud"
    private static let fractalWarmTintKey = "beans.dynamicWallpaper.fractal.warmTint"
    private static let fractalWarmthKey = "beans.dynamicWallpaper.fractal.warmth"
    private static let fractalSpeedKey = "beans.dynamicWallpaper.fractal.speed"
    private static let fractalZoomKey = "beans.dynamicWallpaper.fractal.zoom"
    private static let fractalDriftXKey = "beans.dynamicWallpaper.fractal.driftX"
    private static let fractalDriftYKey = "beans.dynamicWallpaper.fractal.driftY"
    private static let fractalWarpKey = "beans.dynamicWallpaper.fractal.warp"
    private static let fractalCoverageKey = "beans.dynamicWallpaper.fractal.coverage"

    private static let ink1Key = "beans.dynamicWallpaper.ink.1"
    private static let ink2Key = "beans.dynamicWallpaper.ink.2"
    private static let ink3Key = "beans.dynamicWallpaper.ink.3"
    private static let ink4Key = "beans.dynamicWallpaper.ink.4"
    private static let inkGlowKey = "beans.dynamicWallpaper.ink.glow"
    private static let inkSpeedKey = "beans.dynamicWallpaper.ink.speed"
    private static let inkScaleKey = "beans.dynamicWallpaper.ink.scale"
    private static let inkWarpKey = "beans.dynamicWallpaper.ink.warp"
    private static let inkHighlightKey = "beans.dynamicWallpaper.ink.highlight"

    private static let chromeShadowKey = "beans.dynamicWallpaper.chrome.shadow"
    private static let chromeSilverKey = "beans.dynamicWallpaper.chrome.silver"
    private static let chromeHighlightKey = "beans.dynamicWallpaper.chrome.highlight"
    private static let chromeTintKey = "beans.dynamicWallpaper.chrome.tint"
    private static let chromeSpeedKey = "beans.dynamicWallpaper.chrome.speed"
    private static let chromeScaleKey = "beans.dynamicWallpaper.chrome.scale"
    private static let chromeWarpKey = "beans.dynamicWallpaper.chrome.warp"
    private static let chromeContrastKey = "beans.dynamicWallpaper.chrome.contrast"
    private static let chromeSpecPowerKey = "beans.dynamicWallpaper.chrome.specPower"
    private static let chromeSpecStrengthKey = "beans.dynamicWallpaper.chrome.specStrength"
    private static let chromeTintStrengthKey = "beans.dynamicWallpaper.chrome.tintStrength"

    private init() {
        let defaults = UserDefaults.standard

        kind = BeansDynamicWallpaperKind(rawValue: defaults.string(forKey: Self.kindKey) ?? "") ?? .off

        fractalSkyHex = defaults.string(forKey: Self.fractalSkyKey) ?? "#1A2659"
        fractalCloudHex = defaults.string(forKey: Self.fractalCloudKey) ?? "#E6E6FF"
        fractalWarmTintHex = defaults.string(forKey: Self.fractalWarmTintKey) ?? "#1A0D00"
        fractalWarmth = defaults.object(forKey: Self.fractalWarmthKey) as? Double ?? 0.5
        fractalSpeed = defaults.object(forKey: Self.fractalSpeedKey) as? Double ?? 1.0
        fractalZoom = defaults.object(forKey: Self.fractalZoomKey) as? Double ?? 3.0
        fractalDriftX = defaults.object(forKey: Self.fractalDriftXKey) as? Double ?? 0.08
        fractalDriftY = defaults.object(forKey: Self.fractalDriftYKey) as? Double ?? 0.04
        fractalWarp = defaults.object(forKey: Self.fractalWarpKey) as? Double ?? 2.0
        fractalCoverage = defaults.object(forKey: Self.fractalCoverageKey) as? Double ?? 0.0

        ink1Hex = defaults.string(forKey: Self.ink1Key) ?? "#0D001A"
        ink2Hex = defaults.string(forKey: Self.ink2Key) ?? "#1A3380"
        ink3Hex = defaults.string(forKey: Self.ink3Key) ?? "#661A4D"
        ink4Hex = defaults.string(forKey: Self.ink4Key) ?? "#004D66"
        inkGlowHex = defaults.string(forKey: Self.inkGlowKey) ?? "#4D3366"
        inkSpeed = defaults.object(forKey: Self.inkSpeedKey) as? Double ?? 1.0
        inkScale = defaults.object(forKey: Self.inkScaleKey) as? Double ?? 1.8
        inkWarp = defaults.object(forKey: Self.inkWarpKey) as? Double ?? 4.0
        inkHighlight = defaults.object(forKey: Self.inkHighlightKey) as? Double ?? 1.0

        chromeShadowHex = defaults.string(forKey: Self.chromeShadowKey) ?? "#05030D"
        chromeSilverHex = defaults.string(forKey: Self.chromeSilverKey) ?? "#333340"
        chromeHighlightHex = defaults.string(forKey: Self.chromeHighlightKey) ?? "#808099"
        chromeTintHex = defaults.string(forKey: Self.chromeTintKey) ?? "#263366"
        chromeSpeed = defaults.object(forKey: Self.chromeSpeedKey) as? Double ?? 0.3
        chromeScale = defaults.object(forKey: Self.chromeScaleKey) as? Double ?? 2.0
        chromeWarp = defaults.object(forKey: Self.chromeWarpKey) as? Double ?? 1.5
        chromeContrast = defaults.object(forKey: Self.chromeContrastKey) as? Double ?? 0.6
        chromeSpecPower = defaults.object(forKey: Self.chromeSpecPowerKey) as? Double ?? 12.0
        chromeSpecStrength = defaults.object(forKey: Self.chromeSpecStrengthKey) as? Double ?? 0.3
        chromeTintStrength = defaults.object(forKey: Self.chromeTintStrengthKey) as? Double ?? 0.15
    }

    func reloadFromDefaults() {
        let defaults = UserDefaults.standard
        kind = BeansDynamicWallpaperKind(rawValue: defaults.string(forKey: Self.kindKey) ?? "") ?? .off

        fractalSkyHex = defaults.string(forKey: Self.fractalSkyKey) ?? "#1A2659"
        fractalCloudHex = defaults.string(forKey: Self.fractalCloudKey) ?? "#E6E6FF"
        fractalWarmTintHex = defaults.string(forKey: Self.fractalWarmTintKey) ?? "#1A0D00"
        fractalWarmth = defaults.object(forKey: Self.fractalWarmthKey) as? Double ?? 0.5
        fractalSpeed = defaults.object(forKey: Self.fractalSpeedKey) as? Double ?? 1.0
        fractalZoom = defaults.object(forKey: Self.fractalZoomKey) as? Double ?? 3.0
        fractalDriftX = defaults.object(forKey: Self.fractalDriftXKey) as? Double ?? 0.08
        fractalDriftY = defaults.object(forKey: Self.fractalDriftYKey) as? Double ?? 0.04
        fractalWarp = defaults.object(forKey: Self.fractalWarpKey) as? Double ?? 2.0
        fractalCoverage = defaults.object(forKey: Self.fractalCoverageKey) as? Double ?? 0.0

        ink1Hex = defaults.string(forKey: Self.ink1Key) ?? "#0D001A"
        ink2Hex = defaults.string(forKey: Self.ink2Key) ?? "#1A3380"
        ink3Hex = defaults.string(forKey: Self.ink3Key) ?? "#661A4D"
        ink4Hex = defaults.string(forKey: Self.ink4Key) ?? "#004D66"
        inkGlowHex = defaults.string(forKey: Self.inkGlowKey) ?? "#4D3366"
        inkSpeed = defaults.object(forKey: Self.inkSpeedKey) as? Double ?? 1.0
        inkScale = defaults.object(forKey: Self.inkScaleKey) as? Double ?? 1.8
        inkWarp = defaults.object(forKey: Self.inkWarpKey) as? Double ?? 4.0
        inkHighlight = defaults.object(forKey: Self.inkHighlightKey) as? Double ?? 1.0

        chromeShadowHex = defaults.string(forKey: Self.chromeShadowKey) ?? "#05030D"
        chromeSilverHex = defaults.string(forKey: Self.chromeSilverKey) ?? "#333340"
        chromeHighlightHex = defaults.string(forKey: Self.chromeHighlightKey) ?? "#808099"
        chromeTintHex = defaults.string(forKey: Self.chromeTintKey) ?? "#263366"
        chromeSpeed = defaults.object(forKey: Self.chromeSpeedKey) as? Double ?? 0.3
        chromeScale = defaults.object(forKey: Self.chromeScaleKey) as? Double ?? 2.0
        chromeWarp = defaults.object(forKey: Self.chromeWarpKey) as? Double ?? 1.5
        chromeContrast = defaults.object(forKey: Self.chromeContrastKey) as? Double ?? 0.6
        chromeSpecPower = defaults.object(forKey: Self.chromeSpecPowerKey) as? Double ?? 12.0
        chromeSpecStrength = defaults.object(forKey: Self.chromeSpecStrengthKey) as? Double ?? 0.3
        chromeTintStrength = defaults.object(forKey: Self.chromeTintStrengthKey) as? Double ?? 0.15
    }

    func resetCurrent() {
        switch kind {
        case .off:
            break
        case .fractalClouds:
            fractalSkyHex = "#1A2659"
            fractalCloudHex = "#E6E6FF"
            fractalWarmTintHex = "#1A0D00"
            fractalWarmth = 0.5
            fractalSpeed = 1.0
            fractalZoom = 3.0
            fractalDriftX = 0.08
            fractalDriftY = 0.04
            fractalWarp = 2.0
            fractalCoverage = 0.0
        case .inkSmoke:
            ink1Hex = "#0D001A"
            ink2Hex = "#1A3380"
            ink3Hex = "#661A4D"
            ink4Hex = "#004D66"
            inkGlowHex = "#4D3366"
            inkSpeed = 1.0
            inkScale = 1.8
            inkWarp = 4.0
            inkHighlight = 1.0
        case .liquidChrome:
            chromeShadowHex = "#05030D"
            chromeSilverHex = "#333340"
            chromeHighlightHex = "#808099"
            chromeTintHex = "#263366"
            chromeSpeed = 0.3
            chromeScale = 2.0
            chromeWarp = 1.5
            chromeContrast = 0.6
            chromeSpecPower = 12.0
            chromeSpecStrength = 0.3
            chromeTintStrength = 0.15
        }
    }

    func color(_ hex: String, fallback: Color) -> Color {
        Color(hex: hex) ?? fallback
    }

    private func save(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
