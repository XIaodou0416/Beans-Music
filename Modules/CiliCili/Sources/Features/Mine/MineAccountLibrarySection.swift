import SwiftUI

struct MineAccountLibrarySection: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var accountMessageViewModel: AccountMessageCenterViewModel
    let isLoggedIn: Bool
    let onOpenRoute: (MineOverlayRoute) -> Void

    var body: some View {
        Section {
            if isLoggedIn {
                MineOverlayNavigationButton {
                    onOpenRoute(.accountMessages)
                } label: {
                    AccountLibraryButtonRow(
                        title: "账号消息",
                        systemImage: "bell.badge",
                        badgeText: accountMessageViewModel.totalUnreadBadgeText
                    )
                }
            }

            MineOverlayNavigationButton {
                onOpenRoute(.history)
            } label: {
                AccountLibraryButtonRow(
                    title: "观看记录",
                    systemImage: "clock.arrow.circlepath"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.favorites)
            } label: {
                AccountLibraryButtonRow(
                    title: "账号收藏",
                    systemImage: "star"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.watchLater)
            } label: {
                AccountLibraryButtonRow(
                    title: "稍后再看",
                    systemImage: "clock.badge.checkmark"
                )
            }
        } header: {
            Text("账号内容")
        }
    }
}
