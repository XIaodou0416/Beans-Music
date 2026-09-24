import SwiftUI
import UIKit

struct PlaybackDetailChromeHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct PlaybackDetailViewChrome: ViewModifier {
    let navigationBarVisibility: Visibility?
    let hidesBackButton: Bool

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(hidesBackButton)
            .toolbarBackground(.hidden, for: .navigationBar)
            .playbackDetailNavigationBarVisibility(navigationBarVisibility)
    }
}

private struct PlaybackDetailNavigationBarVisibilityModifier: ViewModifier {
    let visibility: Visibility?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let visibility {
            content.toolbar(visibility, for: .navigationBar)
        } else {
            content
        }
    }
}

private struct PlaybackDetailSystemChrome: ViewModifier {
    let isHidden: Bool
    let statusBarStyle: UIStatusBarStyle

    func body(content: Content) -> some View {
        content
            .statusBar(hidden: isHidden)
            .persistentSystemOverlays(isHidden ? .hidden : .visible)
            .background {
                StatusBarStyleBridge(style: statusBarStyle, isHidden: isHidden)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func playbackDetailViewChrome(
        navigationBarVisibility: Visibility? = nil,
        hidesBackButton: Bool = false
    ) -> some View {
        modifier(
            PlaybackDetailViewChrome(
                navigationBarVisibility: navigationBarVisibility,
                hidesBackButton: hidesBackButton
            )
        )
    }

    func playbackDetailNavigationBarVisibility(_ visibility: Visibility?) -> some View {
        modifier(PlaybackDetailNavigationBarVisibilityModifier(visibility: visibility))
    }

    func playbackDetailSystemChrome(
        isHidden: Bool,
        statusBarStyle: UIStatusBarStyle = .lightContent
    ) -> some View {
        modifier(
            PlaybackDetailSystemChrome(
                isHidden: isHidden,
                statusBarStyle: statusBarStyle
            )
        )
    }
}
