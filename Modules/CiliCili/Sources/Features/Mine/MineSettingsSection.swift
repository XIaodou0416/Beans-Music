import SwiftUI

struct MineSettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore
    let onOpenRoute: (MineOverlayRoute) -> Void

    var body: some View {
        Section("设置") {
            MineOverlayNavigationButton {
                onOpenRoute(.interfaceSettings)
            } label: {
                SettingsNavigationRow(
                    title: "界面显示",
                    subtitle: interfaceSettingsSummary,
                    systemImage: "paintpalette"
                )
            }
            .accessibilityIdentifier("mine.settings.interface")

            MineOverlayNavigationButton {
                onOpenRoute(.homeAndSearchSettings)
            } label: {
                SettingsNavigationRow(
                    title: "首页与搜索",
                    subtitle: homeAndSearchSummary,
                    systemImage: "house"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.playbackSettings)
            } label: {
                SettingsNavigationRow(
                    title: "播放偏好",
                    subtitle: playbackSettingsSummary,
                    systemImage: "play.rectangle"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.contentFilterSettings)
            } label: {
                SettingsNavigationRow(
                    title: "内容过滤",
                    subtitle: contentFilterSummary,
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.privacySettings)
            } label: {
                SettingsNavigationRow(
                    title: "隐私",
                    subtitle: privacySummary,
                    systemImage: "hand.raised"
                )
            }

        }
    }

    private var interfaceSettingsSummary: String {
        let tabs = libraryStore.visibleRootTabs
            .filter(\.participatesInRootTabVisibilitySettings)
            .map(\.title)
            .joined(separator: "、")
        return "\(libraryStore.appearanceMode.title) · \(tabs)"
    }

    private var homeAndSearchSummary: String {
        let hotSearch = libraryStore.showsHotSearches ? "热搜开启" : "热搜关闭"
        return "\(libraryStore.homeFeedLayout.title) · \(libraryStore.homeRecommendFeedSourcePreference.title) · \(hotSearch)"
    }

    private var privacySummary: String {
        var enabled = [String]()
        if libraryStore.incognitoModeEnabled {
            enabled.append("无痕")
        }
        if libraryStore.guestModeEnabled {
            enabled.append("游客")
        }
        return enabled.isEmpty ? "默认" : enabled.joined(separator: "、")
    }

    private var contentFilterSummary: String {
        var parts = ["动态 \(libraryStore.blockedDynamicKeywords.count) 个关键词"]
        if libraryStore.videoRecommendationFilterConfiguration.isActive {
            parts.append("推荐过滤开启")
        }
        return parts.joined(separator: "，")
    }

    private var playbackSettingsSummary: String {
        var parts = [
            libraryStore.playbackAutoOptimizationMode.title,
            libraryStore.videoDetailAutoplayEnabled ? "详情自动播放" : "详情手动播放",
            libraryStore.videoCodecPreference.title,
            libraryStore.dolbyVisionRenderingPolicy.title
        ]
        if libraryStore.forceHardwareDecodeEnabled {
            parts.append("硬解优先")
        }
        return parts.joined(separator: " · ")
    }
}
