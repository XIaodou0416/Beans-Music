import SwiftUI

struct MineContentView: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var accountMessageViewModel: AccountMessageCenterViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage(CiliCiliPlaybackExperience.storageKey)
    private var playbackExperienceRaw = CiliCiliPlaybackExperience.defaultRawValue
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void
    let onOpenRoute: (MineOverlayRoute) -> Void

    var body: some View {
        Form {
            MineAccountSection(
                viewModel: viewModel,
                sessionStore: sessionStore,
                libraryStore: libraryStore,
                onQRCodeLogin: onQRCodeLogin,
                onSMSLogin: onSMSLogin,
                onWebLogin: onWebLogin,
                onOpenRoute: onOpenRoute
            )

            MineAccountLibrarySection(
                viewModel: viewModel,
                accountMessageViewModel: accountMessageViewModel,
                isLoggedIn: sessionStore.isLoggedIn,
                onOpenRoute: onOpenRoute
            )

            Section("视频播放") {
                Picker("播放模式", selection: $playbackExperienceRaw) {
                    ForEach(CiliCiliPlaybackExperience.allCases) { experience in
                        Text(experience.title).tag(experience.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("mine.video-playback-mode")
            }

        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .nativeTopScrollEdgeEffect()
    }
}
