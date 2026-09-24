import SwiftUI

struct HomeFeedNavigationChrome: ViewModifier {
    @Environment(\.rootNavigationTitleHidden) private var rootNavigationTitleHidden
    @ObservedObject var viewModel: HomeViewModel
    let modeActions: HomeFeedModeActions
    let scrollActions: HomeFeedScrollActions
    let nativeRefreshActionStore: HomeNativeRefreshActionStore
    let accountMessageViewModel: AccountMessageCenterViewModel?
    let isDetailPresented: Bool
    let onOpenAccountMessages: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    navigationTitle
                        .font(.headline)
                        .opacity(navigationChromeOpacity)
                        .accessibilityHidden(hidesNavigationChrome)
                        .animation(.smooth(duration: 0.18), value: hidesNavigationChrome)
                }
                ToolbarItem(placement: .topBarLeading) {
                    HomeFeedModeMenu(currentMode: viewModel.mode, onSelectMode: switchMode)
                        .opacity(navigationChromeOpacity)
                        .disabled(hidesNavigationChrome)
                        .accessibilityHidden(hidesNavigationChrome)
                        .animation(.smooth(duration: 0.18), value: hidesNavigationChrome)
                }
                .sharedBackgroundVisibility(toolbarItemBackgroundVisibility)
                ToolbarItem(placement: .topBarTrailing) {
                    accountMessageButton
                        .opacity(navigationChromeOpacity)
                        .disabled(hidesNavigationChrome)
                        .accessibilityHidden(hidesNavigationChrome)
                        .animation(.smooth(duration: 0.18), value: hidesNavigationChrome)
                }
                .sharedBackgroundVisibility(toolbarItemBackgroundVisibility)
            }
            .nativeTopNavigationChrome()
    }

    @ViewBuilder
    private var navigationTitle: some View {
        ZStack {
            if viewModel.mode == .recommend {
                modeTitle(.recommend, transitionEdge: .leading)
            } else {
                modeTitle(.popular, transitionEdge: .trailing)
            }
        }
        .frame(width: 64, height: 24)
        .clipped()
        .animation(.smooth(duration: 0.28), value: viewModel.mode)
    }

    private func modeTitle(_ mode: HomeFeedMode, transitionEdge: Edge) -> some View {
        Text(mode.title)
            .frame(width: 64, height: 24)
            .transition(.move(edge: transitionEdge))
    }

    private var hidesNavigationChrome: Bool {
        isDetailPresented || rootNavigationTitleHidden.wrappedValue
    }

    private var navigationChromeOpacity: Double {
        hidesNavigationChrome ? 0 : 1
    }

    private var toolbarItemBackgroundVisibility: Visibility {
        hidesNavigationChrome ? .hidden : .automatic
    }

    @ViewBuilder
    private var accountMessageButton: some View {
        if let accountMessageViewModel {
            HomeAccountMessageButton(
                viewModel: accountMessageViewModel,
                action: onOpenAccountMessages
            )
        } else {
            HomeAccountMessageButtonContent(
                hasUnread: false,
                action: onOpenAccountMessages
            )
        }
    }

    private func switchMode(_ mode: HomeFeedMode) {
        modeActions.switchMode(
            mode,
            viewModel: viewModel,
            scrollActions: scrollActions,
            nativeRefreshActionStore: nativeRefreshActionStore
        )
    }
}

extension View {
    func homeFeedNavigationChrome(
        viewModel: HomeViewModel,
        modeActions: HomeFeedModeActions,
        scrollActions: HomeFeedScrollActions,
        nativeRefreshActionStore: HomeNativeRefreshActionStore,
        accountMessageViewModel: AccountMessageCenterViewModel?,
        isDetailPresented: Bool = false,
        onOpenAccountMessages: @escaping () -> Void
    ) -> some View {
        modifier(
            HomeFeedNavigationChrome(
                viewModel: viewModel,
                modeActions: modeActions,
                scrollActions: scrollActions,
                nativeRefreshActionStore: nativeRefreshActionStore,
                accountMessageViewModel: accountMessageViewModel,
                isDetailPresented: isDetailPresented,
                onOpenAccountMessages: onOpenAccountMessages
            )
        )
    }
}

private struct HomeAccountMessageButton: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    let action: () -> Void

    var body: some View {
        HomeAccountMessageButtonContent(
            hasUnread: viewModel.hasUnreadMessages,
            action: action
        )
    }
}

private struct HomeAccountMessageButtonContent: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let hasUnread: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: VideoDetailActionStrip.Metrics.iconSize, weight: .semibold))
                .foregroundStyle(hasUnread ? appTintColor : Color.primary)
        }
        .accessibilityLabel("账号消息")
        .accessibilityValue(hasUnread ? "有未读消息" : "全部已读")
    }
}
