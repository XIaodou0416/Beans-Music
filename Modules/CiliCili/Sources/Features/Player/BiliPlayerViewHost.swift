import SwiftUI

struct BiliPlayerViewHost<PlayerSurface: View>: View {
    let playerSurface: PlayerSurface
    let title: String
    let configuration: BiliPlayerViewConfiguration
    let isPictureInPictureEnabled: Bool
    let lifecycleActions: BiliPlayerLifecycleActions

    var body: some View {
        content
            .biliPlayerLifecycle(
                isFullscreenActive: configuration.isFullscreenActive,
                presentation: configuration.presentation,
                isLayoutTransitioning: configuration.isLayoutTransitioning,
                isSecondaryControlsPresented: configuration.isSecondaryControlsPresented,
                isPictureInPictureEnabled: isPictureInPictureEnabled,
                actions: lifecycleActions
            )
    }

    @ViewBuilder
    private var content: some View {
        if configuration.keepsPlayerSurfaceStable {
            stableSurface
        } else if configuration.presentation == .embedded {
            embeddedSurface
        } else {
            fullscreenSurface
        }
    }

    private var stableSurface: some View {
        playerSurface
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipped()
    }

    private var embeddedSurface: some View {
        Color.black
            .aspectRatio(max(configuration.embeddedAspectRatio, 0.3), contentMode: .fit)
            .overlay {
                playerSurface
            }
            .clipped()
    }

    @ViewBuilder
    private var fullscreenSurface: some View {
        if configuration.showsNavigationChrome {
            playerSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .ignoresContainerSafeArea(configuration.ignoresContainerSafeArea)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            playerSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .ignoresContainerSafeArea(configuration.ignoresContainerSafeArea)
        }
    }
}

private extension View {
    @ViewBuilder
    func ignoresContainerSafeArea(_ isEnabled: Bool) -> some View {
        if isEnabled {
            ignoresSafeArea()
        } else {
            self
        }
    }
}
