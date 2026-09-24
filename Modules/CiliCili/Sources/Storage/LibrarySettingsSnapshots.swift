import Combine
import SwiftUI

struct RootRuntimeSettingsSnapshot: Equatable {
    var appearanceMode: AppAppearanceMode = .system
    var minimizesTabBarOnScroll = true
    var visibleRootTabs: [AppTab] = AppTab.defaultVisibleTabs
}

@MainActor
final class RootRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = RootRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var appearanceMode: AppAppearanceMode { snapshot.appearanceMode }
    var minimizesTabBarOnScroll: Bool { snapshot.minimizesTabBarOnScroll }
    var visibleRootTabs: [AppTab] { snapshot.visibleRootTabs }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = RootRuntimeSettingsSnapshot(
            appearanceMode: libraryStore.appearanceMode,
            minimizesTabBarOnScroll: libraryStore.minimizesTabBarOnScroll,
            visibleRootTabs: libraryStore.visibleRootTabs
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct HomeRuntimeSettingsSnapshot: Equatable {
    var homeFeedLayout: HomeFeedLayout = LibraryStore.defaultHomeFeedLayout
    var homeRefreshTriggerDistance: Double = LibraryStore.defaultHomeRefreshTriggerDistance
}

@MainActor
final class HomeRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = HomeRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var homeFeedLayout: HomeFeedLayout { snapshot.homeFeedLayout }
    var homeRefreshTriggerDistance: Double { snapshot.homeRefreshTriggerDistance }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = HomeRuntimeSettingsSnapshot(
            homeFeedLayout: libraryStore.homeFeedLayout,
            homeRefreshTriggerDistance: libraryStore.homeRefreshTriggerDistance
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct PullRefreshRuntimeSettingsSnapshot: Equatable {
    var triggerDistance: Double = LibraryStore.defaultHomeRefreshTriggerDistance
}

@MainActor
final class PullRefreshRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = PullRefreshRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var triggerDistance: Double { snapshot.triggerDistance }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = PullRefreshRuntimeSettingsSnapshot(
            triggerDistance: libraryStore.homeRefreshTriggerDistance
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct VideoDetailRuntimeSettingsSnapshot: Equatable {
    var playerPerformanceOverlayEnabled = false
    var videoRotationFrameReportOverlayEnabled = false
    var pictureInPictureEnabled = false
    var appTintColorHex = LibraryStore.defaultAppTintColorHex
    var defaultPlaybackRate = 1.0
    var showsNetworkDiagnosticsButton = false
    var showsPinnedProgressBar = false
    var preferredVideoQuality: Int? = LibraryStore.defaultPreferredVideoQuality
    var effectivePlaybackCDNPreference: PlaybackCDNPreference = .automatic
    var playbackAutoOptimizationEnabled = true
    var minimizesTabBarOnScroll = true
    var defersVideoDetailSecondaryContent = true
}

@MainActor
final class VideoDetailRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = VideoDetailRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var playerPerformanceOverlayEnabled: Bool { snapshot.playerPerformanceOverlayEnabled }
    var videoRotationFrameReportOverlayEnabled: Bool { snapshot.videoRotationFrameReportOverlayEnabled }
    var pictureInPictureEnabled: Bool { snapshot.pictureInPictureEnabled }
    var appTintColor: Color { AppThemeTintColor.color(for: snapshot.appTintColorHex) }
    var defaultPlaybackRate: Double { snapshot.defaultPlaybackRate }
    var showsNetworkDiagnosticsButton: Bool { snapshot.showsNetworkDiagnosticsButton }
    var showsPinnedProgressBar: Bool { snapshot.showsPinnedProgressBar }
    var preferredVideoQuality: Int? { snapshot.preferredVideoQuality }
    var effectivePlaybackCDNPreference: PlaybackCDNPreference { snapshot.effectivePlaybackCDNPreference }
    var playbackAutoOptimizationEnabled: Bool { snapshot.playbackAutoOptimizationEnabled }
    var minimizesTabBarOnScroll: Bool { snapshot.minimizesTabBarOnScroll }
    var defersVideoDetailSecondaryContent: Bool { snapshot.defersVideoDetailSecondaryContent }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = VideoDetailRuntimeSettingsSnapshot(
            playerPerformanceOverlayEnabled: libraryStore.playerPerformanceOverlayEnabled,
            videoRotationFrameReportOverlayEnabled: libraryStore.videoRotationFrameReportOverlayEnabled,
            pictureInPictureEnabled: libraryStore.pictureInPictureEnabled,
            appTintColorHex: libraryStore.appTintColorHex,
            defaultPlaybackRate: libraryStore.defaultPlaybackRate,
            showsNetworkDiagnosticsButton: libraryStore.showsVideoDetailNetworkDiagnosticsButton,
            showsPinnedProgressBar: libraryStore.showsVideoDetailPinnedProgressBar,
            preferredVideoQuality: libraryStore.effectivePreferredVideoQuality,
            effectivePlaybackCDNPreference: libraryStore.effectivePlaybackCDNPreference,
            playbackAutoOptimizationEnabled: libraryStore.isPlaybackAutoOptimizationEnabled,
            minimizesTabBarOnScroll: libraryStore.minimizesTabBarOnScroll,
            defersVideoDetailSecondaryContent: true
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

struct DynamicCommentsRuntimeSettingsSnapshot: Equatable {
    var blocksGoodsComments = true
}

@MainActor
final class DynamicCommentsRuntimeSettingsStore: ObservableObject {
    @Published private(set) var snapshot = DynamicCommentsRuntimeSettingsSnapshot()
    private weak var libraryStore: LibraryStore?
    private var cancellable: AnyCancellable?

    var blocksGoodsComments: Bool { snapshot.blocksGoodsComments }

    func bind(_ libraryStore: LibraryStore) {
        guard self.libraryStore !== libraryStore else {
            refresh()
            return
        }
        self.libraryStore = libraryStore
        refresh()
        cancellable = libraryStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let libraryStore else { return }
        let next = DynamicCommentsRuntimeSettingsSnapshot(
            blocksGoodsComments: libraryStore.blocksGoodsComments
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}
