import SwiftUI
import UIKit

/// App icon presets are declared here so newly bundled icons can be enabled without changing the settings UI.
enum BeansAppIconPreset: String, CaseIterable, Identifiable {
    case standard
    case stretch
    case soles
    case sideHug
    case foldedArms
    case shy
    case heart
    case wave
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "默认图标"
        case .stretch: return "举手"
        case .soles: return "脚印"
        case .sideHug: return "侧抱"
        case .foldedArms: return "抱臂"
        case .shy: return "托腮"
        case .heart: return "爱心"
        case .wave: return "挥手"
        case .night: return "夜色"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .standard: return nil
        case .stretch: return "AppIconStretch"
        case .soles: return "AppIconSoles"
        case .sideHug: return "AppIconSideHug"
        case .foldedArms: return "AppIconFoldedArms"
        case .shy: return "AppIconShy"
        case .heart: return "AppIconHeart"
        case .wave: return "AppIconWave"
        case .night: return "AppIconNight"
        }
    }

    var previewAssetName: String {
        switch self {
        case .standard: return "AppIconPreviewDefault"
        case .stretch: return "AppIconPreviewStretch"
        case .soles: return "AppIconPreviewSoles"
        case .sideHug: return "AppIconPreviewSideHug"
        case .foldedArms: return "AppIconPreviewFoldedArms"
        case .shy: return "AppIconPreviewShy"
        case .heart: return "AppIconPreviewHeart"
        case .wave: return "AppIconPreviewWave"
        case .night: return "AppIconPreviewNight"
        }
    }
}

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var currentPreset: BeansAppIconPreset

    private let storageKey = "beans.appIconPreset"

    private init() {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        currentPreset = BeansAppIconPreset.allCases.first(where: {
            $0.alternateIconName == UIApplication.shared.alternateIconName
        }) ?? BeansAppIconPreset(rawValue: stored ?? "") ?? .standard
    }

    func select(_ preset: BeansAppIconPreset) {
        let applySelection = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(preset.rawValue, forKey: self.storageKey)
            self.currentPreset = preset
        }

        guard UIApplication.shared.alternateIconName != preset.alternateIconName else {
            applySelection()
            return
        }

        guard UIApplication.shared.supportsAlternateIcons else {
            ToastCenter.shared.show("软件图标暂不可用")
            return
        }

        UIApplication.shared.setAlternateIconName(preset.alternateIconName) { error in
            guard error == nil else {
                ToastCenter.shared.show("更换软件图标失败")
                return
            }
            Task { @MainActor in
                applySelection()
            }
        }
    }
}

struct AppIconPickerSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var iconManager = AppIconManager.shared

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                List {
                    Section {
                        ForEach(BeansAppIconPreset.allCases) { preset in
                            Button {
                                iconManager.select(preset)
                                BeansHaptics.select()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(preset.previewAssetName)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    Text(preset.title)
                                        .font(BeansFont.appFont(15, .medium))
                                        .foregroundStyle(Color.beansLabel)
                                    Spacer()
                                    if iconManager.currentPreset == preset {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color.beansAmber)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("选择后会更新主屏幕上的软件图标。")
                    }
                }
                .beansScrollContentBackgroundHidden()
            }
            .navigationTitle("软件图标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium], dragIndicator: true))
    }
}
