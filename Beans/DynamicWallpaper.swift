import SwiftUI
import UIKit

/// Built-in animated wallpapers copied from ShipSwift's SwiftUI/Metal effects.
/// The renderers themselves are only available on iOS 17 and newer; older
/// systems keep using the existing static background implementation.
enum BeansDynamicWallpaperKind: String, CaseIterable, Identifiable {
    case off
    case fractalClouds
    case inkSmoke
    case liquidChrome
    case neuroNoise
    case simplexNoise
    case metaballs
    case water

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .fractalClouds: return "Fractal Clouds"
        case .inkSmoke: return "Ink Smoke"
        case .liquidChrome: return "Liquid Chrome"
        case .neuroNoise: return "Neuro Noise"
        case .simplexNoise: return "Simplex Noise"
        case .metaballs: return "Metaballs"
        case .water: return "Water"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "使用现有的颜色或图片壁纸"
        case .fractalClouds: return "分形云层，保留 ShipSwift 原始参数"
        case .inkSmoke: return "墨水扩散，保留 ShipSwift 原始参数"
        case .liquidChrome: return "液态金属，保留 ShipSwift 原始参数"
        case .neuroNoise: return "神经噪声，流动的发光线条"
        case .simplexNoise: return "单纯形噪声，多色渐变流场"
        case .metaballs: return "融合球，柔和的彩色流体形状"
        case .water: return "水面折射，使用你上传的图片作为源内容"
        }
    }

    var icon: String {
        switch self {
        case .off: return "nosign"
        case .fractalClouds: return "cloud.fog.fill"
        case .inkSmoke: return "drop.fill"
        case .liquidChrome: return "circle.lefthalf.filled"
        case .neuroNoise: return "point.3.connected.trianglepath.dotted"
        case .simplexNoise: return "waveform.path.ecg"
        case .metaballs: return "circle.hexagongrid.fill"
        case .water: return "water.waves"
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

    // Neuro Noise
    @Published var neuroFrontHex: String { didSet { save(neuroFrontHex, forKey: Self.neuroFrontKey) } }
    @Published var neuroMidHex: String { didSet { save(neuroMidHex, forKey: Self.neuroMidKey) } }
    @Published var neuroBackHex: String { didSet { save(neuroBackHex, forKey: Self.neuroBackKey) } }
    @Published var neuroSpeed: Double { didSet { save(neuroSpeed, forKey: Self.neuroSpeedKey) } }
    @Published var neuroBrightness: Double { didSet { save(neuroBrightness, forKey: Self.neuroBrightnessKey) } }
    @Published var neuroContrast: Double { didSet { save(neuroContrast, forKey: Self.neuroContrastKey) } }
    @Published var neuroScale: Double { didSet { save(neuroScale, forKey: Self.neuroScaleKey) } }

    // Simplex Noise
    @Published var simplexColorsHex: [String] { didSet { save(simplexColorsHex, forKey: Self.simplexColorsKey) } }
    @Published var simplexScale: Double { didSet { save(simplexScale, forKey: Self.simplexScaleKey) } }
    @Published var simplexStepsPerColor: Double { didSet { save(simplexStepsPerColor, forKey: Self.simplexStepsKey) } }
    @Published var simplexSoftness: Double { didSet { save(simplexSoftness, forKey: Self.simplexSoftnessKey) } }
    @Published var simplexSpeed: Double { didSet { save(simplexSpeed, forKey: Self.simplexSpeedKey) } }

    // Metaballs
    @Published var metaballsStyleRaw: String { didSet { save(metaballsStyleRaw, forKey: Self.metaballsStyleKey) } }
    @Published var metaballsColorsHex: [String] { didSet { save(metaballsColorsHex, forKey: Self.metaballsColorsKey) } }
    @Published var metaballsBackgroundHex: String { didSet { save(metaballsBackgroundHex, forKey: Self.metaballsBackgroundKey) } }
    @Published var metaballsSpeed: Double { didSet { save(metaballsSpeed, forKey: Self.metaballsSpeedKey) } }
    @Published var metaballsCount: Double { didSet { save(metaballsCount, forKey: Self.metaballsCountKey) } }
    @Published var metaballsSize: Double { didSet { save(metaballsSize, forKey: Self.metaballsSizeKey) } }
    @Published var metaballsBigSize: Double { didSet { save(metaballsBigSize, forKey: Self.metaballsBigSizeKey) } }

    // Water
    @Published var waterImageDataBase64: String { didSet { save(waterImageDataBase64, forKey: Self.waterImageKey) } }
    @Published var waterSpeed: Double { didSet { save(waterSpeed, forKey: Self.waterSpeedKey) } }
    @Published var waterSize: Double { didSet { save(waterSize, forKey: Self.waterSizeKey) } }
    @Published var waterCaustic: Double { didSet { save(waterCaustic, forKey: Self.waterCausticKey) } }
    @Published var waterWaves: Double { didSet { save(waterWaves, forKey: Self.waterWavesKey) } }
    @Published var waterLayering: Double { didSet { save(waterLayering, forKey: Self.waterLayeringKey) } }
    @Published var waterEdges: Double { didSet { save(waterEdges, forKey: Self.waterEdgesKey) } }
    @Published var waterHighlights: Double { didSet { save(waterHighlights, forKey: Self.waterHighlightsKey) } }
    @Published var waterBackHex: String { didSet { save(waterBackHex, forKey: Self.waterBackKey) } }
    @Published var waterHighlightHex: String { didSet { save(waterHighlightHex, forKey: Self.waterHighlightKey) } }

    /// Whether the selected dynamic wallpaper should also replace the player's
    /// cover-blur background. The normal app pages still follow the existing
    /// background synchronization option.
    @Published var syncToPlayer: Bool { didSet { save(syncToPlayer, forKey: Self.syncToPlayerKey) } }

    // Water is evaluated from a TimelineView. Keep the decoded image alive so
    // animation frames never repeatedly decode the same base64 payload.
    private var cachedWaterImageKey = ""
    private var cachedWaterImage: UIImage?

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

    private static let neuroFrontKey = "beans.dynamicWallpaper.neuro.front"
    private static let neuroMidKey = "beans.dynamicWallpaper.neuro.mid"
    private static let neuroBackKey = "beans.dynamicWallpaper.neuro.back"
    private static let neuroSpeedKey = "beans.dynamicWallpaper.neuro.speed"
    private static let neuroBrightnessKey = "beans.dynamicWallpaper.neuro.brightness"
    private static let neuroContrastKey = "beans.dynamicWallpaper.neuro.contrast"
    private static let neuroScaleKey = "beans.dynamicWallpaper.neuro.scale"

    private static let simplexColorsKey = "beans.dynamicWallpaper.simplex.colors"
    private static let simplexScaleKey = "beans.dynamicWallpaper.simplex.scale"
    private static let simplexStepsKey = "beans.dynamicWallpaper.simplex.steps"
    private static let simplexSoftnessKey = "beans.dynamicWallpaper.simplex.softness"
    private static let simplexSpeedKey = "beans.dynamicWallpaper.simplex.speed"

    private static let metaballsStyleKey = "beans.dynamicWallpaper.metaballs.style"
    private static let metaballsColorsKey = "beans.dynamicWallpaper.metaballs.colors"
    private static let metaballsBackgroundKey = "beans.dynamicWallpaper.metaballs.background"
    private static let metaballsSpeedKey = "beans.dynamicWallpaper.metaballs.speed"
    private static let metaballsCountKey = "beans.dynamicWallpaper.metaballs.count"
    private static let metaballsSizeKey = "beans.dynamicWallpaper.metaballs.size"
    private static let metaballsBigSizeKey = "beans.dynamicWallpaper.metaballs.bigSize"

    private static let waterImageKey = "beans.dynamicWallpaper.water.image"
    private static let waterSpeedKey = "beans.dynamicWallpaper.water.speed"
    private static let waterSizeKey = "beans.dynamicWallpaper.water.size"
    private static let waterCausticKey = "beans.dynamicWallpaper.water.caustic"
    private static let waterWavesKey = "beans.dynamicWallpaper.water.waves"
    private static let waterLayeringKey = "beans.dynamicWallpaper.water.layering"
    private static let waterEdgesKey = "beans.dynamicWallpaper.water.edges"
    private static let waterHighlightsKey = "beans.dynamicWallpaper.water.highlights"
    private static let waterBackKey = "beans.dynamicWallpaper.water.back"
    private static let waterHighlightKey = "beans.dynamicWallpaper.water.highlight"
    private static let syncToPlayerKey = "beans.dynamicWallpaper.syncToPlayer"

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

        neuroFrontHex = defaults.string(forKey: Self.neuroFrontKey) ?? "#FFFFFF"
        neuroMidHex = defaults.string(forKey: Self.neuroMidKey) ?? "#56CDE3"
        neuroBackHex = defaults.string(forKey: Self.neuroBackKey) ?? "#050519"
        neuroSpeed = defaults.object(forKey: Self.neuroSpeedKey) as? Double ?? 1.0
        neuroBrightness = defaults.object(forKey: Self.neuroBrightnessKey) as? Double ?? 0.5
        neuroContrast = defaults.object(forKey: Self.neuroContrastKey) as? Double ?? 0.5
        neuroScale = defaults.object(forKey: Self.neuroScaleKey) as? Double ?? 0.8

        simplexColorsHex = defaults.stringArray(forKey: Self.simplexColorsKey) ?? ["#FF0000", "#0000FF", "#FFFF00", "#000000", "#A52A2A", "#00FFFF"]
        simplexScale = defaults.object(forKey: Self.simplexScaleKey) as? Double ?? 0.05
        simplexStepsPerColor = defaults.object(forKey: Self.simplexStepsKey) as? Double ?? 1.0
        simplexSoftness = defaults.object(forKey: Self.simplexSoftnessKey) as? Double ?? 0.0
        simplexSpeed = defaults.object(forKey: Self.simplexSpeedKey) as? Double ?? 1.0

        metaballsStyleRaw = defaults.string(forKey: Self.metaballsStyleKey) ?? SWMetaballsStyle.cluster.rawValue
        metaballsColorsHex = defaults.stringArray(forKey: Self.metaballsColorsKey) ?? ["#FF0000", "#00FF00", "#FFFFFF", "#FFFF00", "#0000FF", "#00FFFF", "#800080"]
        metaballsBackgroundHex = defaults.string(forKey: Self.metaballsBackgroundKey) ?? "#000000"
        metaballsSpeed = defaults.object(forKey: Self.metaballsSpeedKey) as? Double ?? 1.0
        metaballsCount = defaults.object(forKey: Self.metaballsCountKey) as? Double ?? 8.0
        metaballsSize = defaults.object(forKey: Self.metaballsSizeKey) as? Double ?? 0.8
        metaballsBigSize = defaults.object(forKey: Self.metaballsBigSizeKey) as? Double ?? 0.85

        waterImageDataBase64 = defaults.string(forKey: Self.waterImageKey) ?? ""
        waterSpeed = defaults.object(forKey: Self.waterSpeedKey) as? Double ?? 1.0
        waterSize = defaults.object(forKey: Self.waterSizeKey) as? Double ?? 1.0
        waterCaustic = defaults.object(forKey: Self.waterCausticKey) as? Double ?? 0.1
        waterWaves = defaults.object(forKey: Self.waterWavesKey) as? Double ?? 0.08
        waterLayering = defaults.object(forKey: Self.waterLayeringKey) as? Double ?? 0.15
        waterEdges = defaults.object(forKey: Self.waterEdgesKey) as? Double ?? 0.3
        waterHighlights = defaults.object(forKey: Self.waterHighlightsKey) as? Double ?? 0.35
        waterBackHex = defaults.string(forKey: Self.waterBackKey) ?? "#000000"
        waterHighlightHex = defaults.string(forKey: Self.waterHighlightKey) ?? "#FFFFFF"
        syncToPlayer = defaults.object(forKey: Self.syncToPlayerKey) as? Bool ?? false
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

        neuroFrontHex = defaults.string(forKey: Self.neuroFrontKey) ?? "#FFFFFF"
        neuroMidHex = defaults.string(forKey: Self.neuroMidKey) ?? "#56CDE3"
        neuroBackHex = defaults.string(forKey: Self.neuroBackKey) ?? "#050519"
        neuroSpeed = defaults.object(forKey: Self.neuroSpeedKey) as? Double ?? 1.0
        neuroBrightness = defaults.object(forKey: Self.neuroBrightnessKey) as? Double ?? 0.5
        neuroContrast = defaults.object(forKey: Self.neuroContrastKey) as? Double ?? 0.5
        neuroScale = defaults.object(forKey: Self.neuroScaleKey) as? Double ?? 0.8

        simplexColorsHex = defaults.stringArray(forKey: Self.simplexColorsKey) ?? ["#FF0000", "#0000FF", "#FFFF00", "#000000", "#A52A2A", "#00FFFF"]
        simplexScale = defaults.object(forKey: Self.simplexScaleKey) as? Double ?? 0.05
        simplexStepsPerColor = defaults.object(forKey: Self.simplexStepsKey) as? Double ?? 1.0
        simplexSoftness = defaults.object(forKey: Self.simplexSoftnessKey) as? Double ?? 0.0
        simplexSpeed = defaults.object(forKey: Self.simplexSpeedKey) as? Double ?? 1.0

        metaballsStyleRaw = defaults.string(forKey: Self.metaballsStyleKey) ?? SWMetaballsStyle.cluster.rawValue
        metaballsColorsHex = defaults.stringArray(forKey: Self.metaballsColorsKey) ?? ["#FF0000", "#00FF00", "#FFFFFF", "#FFFF00", "#0000FF", "#00FFFF", "#800080"]
        metaballsBackgroundHex = defaults.string(forKey: Self.metaballsBackgroundKey) ?? "#000000"
        metaballsSpeed = defaults.object(forKey: Self.metaballsSpeedKey) as? Double ?? 1.0
        metaballsCount = defaults.object(forKey: Self.metaballsCountKey) as? Double ?? 8.0
        metaballsSize = defaults.object(forKey: Self.metaballsSizeKey) as? Double ?? 0.8
        metaballsBigSize = defaults.object(forKey: Self.metaballsBigSizeKey) as? Double ?? 0.85

        waterImageDataBase64 = defaults.string(forKey: Self.waterImageKey) ?? ""
        waterSpeed = defaults.object(forKey: Self.waterSpeedKey) as? Double ?? 1.0
        waterSize = defaults.object(forKey: Self.waterSizeKey) as? Double ?? 1.0
        waterCaustic = defaults.object(forKey: Self.waterCausticKey) as? Double ?? 0.1
        waterWaves = defaults.object(forKey: Self.waterWavesKey) as? Double ?? 0.08
        waterLayering = defaults.object(forKey: Self.waterLayeringKey) as? Double ?? 0.15
        waterEdges = defaults.object(forKey: Self.waterEdgesKey) as? Double ?? 0.3
        waterHighlights = defaults.object(forKey: Self.waterHighlightsKey) as? Double ?? 0.35
        waterBackHex = defaults.string(forKey: Self.waterBackKey) ?? "#000000"
        waterHighlightHex = defaults.string(forKey: Self.waterHighlightKey) ?? "#FFFFFF"
        syncToPlayer = defaults.object(forKey: Self.syncToPlayerKey) as? Bool ?? false
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
        case .neuroNoise:
            neuroFrontHex = "#FFFFFF"
            neuroMidHex = "#56CDE3"
            neuroBackHex = "#050519"
            neuroSpeed = 1.0
            neuroBrightness = 0.5
            neuroContrast = 0.5
            neuroScale = 0.8
        case .simplexNoise:
            simplexColorsHex = ["#FF0000", "#0000FF", "#FFFF00", "#000000", "#A52A2A", "#00FFFF"]
            simplexScale = 0.05
            simplexStepsPerColor = 1.0
            simplexSoftness = 0.0
            simplexSpeed = 1.0
        case .metaballs:
            metaballsStyleRaw = SWMetaballsStyle.cluster.rawValue
            metaballsColorsHex = ["#FF0000", "#00FF00", "#FFFFFF", "#FFFF00", "#0000FF", "#00FFFF", "#800080"]
            metaballsBackgroundHex = "#000000"
            metaballsSpeed = 1.0
            metaballsCount = 8.0
            metaballsSize = 0.8
            metaballsBigSize = 0.85
        case .water:
            waterSpeed = 1.0
            waterSize = 1.0
            waterCaustic = 0.1
            waterWaves = 0.08
            waterLayering = 0.15
            waterEdges = 0.3
            waterHighlights = 0.35
            waterBackHex = "#000000"
            waterHighlightHex = "#FFFFFF"
        }
    }

    func color(_ hex: String, fallback: Color) -> Color {
        Color(hex: hex) ?? fallback
    }

    private func save(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Water uses a compressed, bounded image copy so a large camera photo does
    /// not make UserDefaults or the settings backup unwieldy.
    func setWaterImage(_ data: Data?) {
        guard let data, let image = UIImage(data: data) else {
            waterImageDataBase64 = ""
            cachedWaterImageKey = ""
            cachedWaterImage = nil
            return
        }

        let maxDimension: CGFloat = 1600
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        let encoded = (resized.jpegData(compressionQuality: 0.82) ?? data).base64EncodedString()
        waterImageDataBase64 = encoded
        cachedWaterImageKey = ""
        cachedWaterImage = nil
    }

    var waterImage: UIImage? {
        if cachedWaterImageKey == waterImageDataBase64 {
            return cachedWaterImage
        }
        guard let data = Data(base64Encoded: waterImageDataBase64) else { return nil }
        let image = UIImage(data: data)
        cachedWaterImageKey = waterImageDataBase64
        cachedWaterImage = image
        return image
    }

    var syncsDynamicWallpaperToPlayer: Bool {
        syncToPlayer && renderableKind != .off
    }
}

/// Shared renderer used by normal pages and by the full-screen player. The
/// shader views remain unavailable below iOS 17; older systems simply receive
/// a clear layer and keep the existing background implementation.
struct BeansDynamicWallpaperView: View {
    @ObservedObject private var store = DynamicWallpaperStore.shared
    var forPlayer: Bool = false

    var body: some View {
        if #available(iOS 17.0, *), store.renderableKind != .off,
           (!forPlayer || store.syncsDynamicWallpaperToPlayer) {
            renderer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .id("dynamic-wallpaper-\(store.renderableKind.rawValue)-\(forPlayer)")
                .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    @available(iOS 17.0, *)
    private var renderer: some View {
        switch store.renderableKind {
        case .fractalClouds:
            SWFractalClouds(
                skyColor: store.color(store.fractalSkyHex, fallback: Color(red: 0.102, green: 0.149, blue: 0.349)),
                cloudColor: store.color(store.fractalCloudHex, fallback: Color(red: 0.902, green: 0.902, blue: 1.0)),
                warmTint: store.color(store.fractalWarmTintHex, fallback: Color(red: 0.102, green: 0.051, blue: 0.0)),
                warmth: Float(store.fractalWarmth), speed: Float(store.fractalSpeed),
                zoom: Float(store.fractalZoom), driftX: Float(store.fractalDriftX),
                driftY: Float(store.fractalDriftY), warp: Float(store.fractalWarp),
                coverage: Float(store.fractalCoverage)
            )
        case .inkSmoke:
            SWInkSmoke(
                ink1: store.color(store.ink1Hex, fallback: Color(red: 0.051, green: 0.0, blue: 0.102)),
                ink2: store.color(store.ink2Hex, fallback: Color(red: 0.102, green: 0.2, blue: 0.502)),
                ink3: store.color(store.ink3Hex, fallback: Color(red: 0.4, green: 0.102, blue: 0.302)),
                ink4: store.color(store.ink4Hex, fallback: Color(red: 0.0, green: 0.302, blue: 0.4)),
                glow: store.color(store.inkGlowHex, fallback: Color(red: 0.302, green: 0.2, blue: 0.4)),
                speed: Float(store.inkSpeed), scale: Float(store.inkScale),
                warp: Float(store.inkWarp), highlight: Float(store.inkHighlight)
            )
        case .liquidChrome:
            SWLiquidChrome(
                shadow: store.color(store.chromeShadowHex, fallback: Color(red: 0.020, green: 0.012, blue: 0.051)),
                silver: store.color(store.chromeSilverHex, fallback: Color(red: 0.2, green: 0.2, blue: 0.251)),
                highlight: store.color(store.chromeHighlightHex, fallback: Color(red: 0.502, green: 0.502, blue: 0.6)),
                tint: store.color(store.chromeTintHex, fallback: Color(red: 0.149, green: 0.2, blue: 0.4)),
                speed: Float(store.chromeSpeed), scale: Float(store.chromeScale),
                warp: Float(store.chromeWarp), contrast: Float(store.chromeContrast),
                specPower: Float(store.chromeSpecPower), specStrength: Float(store.chromeSpecStrength),
                tintStrength: Float(store.chromeTintStrength)
            )
        case .neuroNoise:
            SWNeuroNoise(
                colorFront: store.color(store.neuroFrontHex, fallback: .white),
                colorMid: store.color(store.neuroMidHex, fallback: Color(red: 0.337, green: 0.804, blue: 0.890)),
                colorBack: store.color(store.neuroBackHex, fallback: Color(red: 0.02, green: 0.02, blue: 0.10)),
                speed: Float(store.neuroSpeed), brightness: Float(store.neuroBrightness),
                contrast: Float(store.neuroContrast), scale: Float(store.neuroScale)
            )
        case .simplexNoise:
            SWSimplexNoise(
                colors: store.simplexColorsHex.map { store.color($0, fallback: .black) },
                scale: Float(store.simplexScale), stepsPerColor: Float(store.simplexStepsPerColor),
                softness: Float(store.simplexSoftness), speed: Float(store.simplexSpeed)
            )
        case .metaballs:
            SWMetaballs(
                style: SWMetaballsStyle(rawValue: store.metaballsStyleRaw) ?? .cluster,
                colors: store.metaballsColorsHex.map { store.color($0, fallback: .white) },
                background: store.color(store.metaballsBackgroundHex, fallback: .black),
                speed: Float(store.metaballsSpeed), count: Int(store.metaballsCount.rounded()),
                size: Float(store.metaballsSize), bigSize: Float(store.metaballsBigSize)
            )
        case .water:
            SWWater(
                speed: Float(store.waterSpeed), size: Float(store.waterSize),
                caustic: Float(store.waterCaustic), waves: Float(store.waterWaves),
                layering: Float(store.waterLayering), edges: Float(store.waterEdges),
                highlights: Float(store.waterHighlights),
                colorBack: store.color(store.waterBackHex, fallback: .black),
                colorHighlight: store.color(store.waterHighlightHex, fallback: .white)
            ) {
                GeometryReader { proxy in
                    Group {
                        if let image = store.waterImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            store.color(store.waterBackHex, fallback: .black)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
            }
        case .off:
            Color.clear
        }
    }
}
