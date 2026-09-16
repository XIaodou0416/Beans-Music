import SwiftUI
import UIKit

/// App icon presets are declared here so newly bundled icons can be enabled without changing the settings UI.
enum BeansAppIconPreset: String, CaseIterable, Identifiable {
    case standard
    case sideHug
    case foldedArms
    case redCharacter
    case blackNote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "默认图标"
        case .sideHug: return "侧抱"
        case .foldedArms: return "抱臂"
        case .redCharacter: return "红色角色"
        case .blackNote: return "黑色音符"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .standard: return nil
        case .sideHug: return "AppIconSideHug"
        case .foldedArms: return "AppIconFoldedArms"
        case .redCharacter: return "AppIconRedCharacter"
        case .blackNote: return "AppIconBlackNote"
        }
    }

    var previewAssetName: String {
        switch self {
        case .standard: return "AppIconPreviewDefault"
        case .sideHug: return "AppIconPreviewSideHug"
        case .foldedArms: return "AppIconPreviewFoldedArms"
        case .redCharacter: return "AppIconPreviewRedCharacter"
        case .blackNote: return "AppIconPreviewBlackNote"
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
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                        spacing: 18
                    ) {
                        ForEach(BeansAppIconPreset.allCases) { preset in
                            Button {
                                iconManager.select(preset)
                                BeansHaptics.select()
                            } label: {
                                Image(preset.previewAssetName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        if iconManager.currentPreset == preset {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundStyle(Color.beansAmber, Color.white)
                                                .padding(6)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.title)
                        }
                    }
                    .padding(18)
                }
                .beansScrollIndicatorsHidden()
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
