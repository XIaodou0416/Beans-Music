import SwiftUI
import UIKit

/// App icon presets are declared here so newly bundled icons can be enabled without changing the settings UI.
enum BeansAppIconPreset: String, CaseIterable, Identifiable {
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "默认图标"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .standard: return nil
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
        currentPreset = BeansAppIconPreset(rawValue: stored ?? "") ?? .standard
    }

    func select(_ preset: BeansAppIconPreset) {
        let applySelection = {
            UserDefaults.standard.set(preset.rawValue, forKey: self.storageKey)
            self.currentPreset = preset
        }

        guard UIApplication.shared.supportsAlternateIcons else {
            applySelection()
            return
        }

        UIApplication.shared.setAlternateIconName(preset.alternateIconName) { error in
            guard error == nil else { return }
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
                                    Image(systemName: "app.fill")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Color.beansAmber)
                                        .frame(width: 30, height: 30)
                                        .background {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.beansAmber.opacity(0.16))
                                        }
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
                        Text("新的预设图标会在后续加入后显示在这里。")
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
