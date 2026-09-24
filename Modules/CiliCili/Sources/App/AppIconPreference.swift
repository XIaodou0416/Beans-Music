import UIKit

enum AppIconPreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色图标"
        case .dark:
            return "深色图标"
        }
    }

    fileprivate var alternateIconName: String? {
        switch self {
        case .system:
            return nil
        case .light:
            return "AppIconLight"
        case .dark:
            return "AppIconDark"
        }
    }
}

@MainActor
enum AppIconController {
    static func apply(_ preference: AppIconPreference) {
        let application = UIApplication.shared
        let alternateIconName = preference.alternateIconName
        guard application.supportsAlternateIcons,
              application.alternateIconName != alternateIconName
        else { return }

        application.setAlternateIconName(alternateIconName)
    }
}
