import Foundation

/// Resolves playback quality from the user's connection-specific preference.
/// Downloads keep their existing independent quality setting.
enum NetworkAudioQuality {
    static let connectionAwareKey = "beans.audioQuality.connectionAware"
    static let wifiOfficialKey = "beans.audioQuality.wifi"
    static let cellularOfficialKey = "beans.audioQuality.cellular"
    static let wifiThirdPartyKey = "beans.thirdPartyAudioQuality.wifi"
    static let cellularThirdPartyKey = "beans.thirdPartyAudioQuality.cellular"

    static var officialPreferred: BeansAudioQuality {
        if let raw = selectedValue(wifiKey: wifiOfficialKey, cellularKey: cellularOfficialKey, fallbackKey: "beans.audioQuality"),
           let quality = BeansAudioQuality(rawValue: raw) {
            return quality
        }
        return .hires
    }

    static var thirdPartyPreferred: ThirdPartyAudioQuality {
        if let raw = selectedValue(
            wifiKey: wifiThirdPartyKey,
            cellularKey: cellularThirdPartyKey,
            fallbackKey: ThirdPartyAudioQuality.storageKey
        ), let quality = ThirdPartyAudioQuality(sourceValue: raw) {
            return quality
        }
        return .kb320
    }

    private static func selectedValue(wifiKey: String, cellularKey: String, fallbackKey: String) -> String? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: connectionAwareKey) else {
            return defaults.string(forKey: fallbackKey)
        }

        switch BeansNetworkStatus.shared.connectionKind {
        case .wifi:
            return defaults.string(forKey: wifiKey) ?? defaults.string(forKey: fallbackKey)
        case .cellular:
            return defaults.string(forKey: cellularKey) ?? defaults.string(forKey: fallbackKey)
        case .other, .unavailable:
            return defaults.string(forKey: fallbackKey)
        }
    }
}
