import Combine
import Foundation
import SwiftUI

struct StoredVideo: Identifiable, Codable, Hashable {
    var id: String { bvid }

    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let desc: String?
    let duration: Int?
    let pubdate: Int?
    let ownerMID: Int?
    let ownerName: String?
    let ownerFace: String?
    let viewCount: Int?
    let cid: Int?
    let savedAt: Date
    let playbackTime: TimeInterval?
    let playbackDuration: TimeInterval?

    init(
        video: VideoItem,
        savedAt: Date,
        cid: Int? = nil,
        playbackTime: TimeInterval? = nil,
        playbackDuration: TimeInterval? = nil
    ) {
        self.bvid = video.bvid
        self.aid = video.aid
        self.title = video.title
        self.pic = video.pic
        self.desc = video.desc
        self.duration = video.duration
        self.pubdate = video.pubdate
        self.ownerMID = video.owner?.mid
        self.ownerName = video.owner?.name
        self.ownerFace = video.owner?.face
        self.viewCount = video.stat?.view
        self.cid = cid ?? video.cid
        self.savedAt = savedAt
        self.playbackTime = playbackTime
        self.playbackDuration = playbackDuration
    }

    var videoItem: VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic,
            desc: desc,
            duration: duration,
            pubdate: pubdate,
            owner: owner,
            stat: VideoStat(view: viewCount, reply: nil, like: nil, coin: nil, favorite: nil),
            cid: cid,
            pages: nil,
            dimension: nil,
            historyResumeTime: resumeTime,
            historyCID: cid
        )
    }

    var resumeTime: TimeInterval? {
        guard let playbackTime,
            playbackTime >= TimeInterval(LibraryStore.defaultPlaybackHistorySyncThresholdSeconds)
        else { return nil }
        if let playbackDuration, playbackDuration > 0 {
            let remaining = playbackDuration - playbackTime
            guard remaining > 15, playbackTime / playbackDuration < 0.96 else { return nil }
        }
        return playbackTime
    }

    var playbackProgress: Double? {
        guard let playbackTime, playbackTime > 0 else { return nil }
        guard let playbackDuration, playbackDuration > 0 else { return nil }
        return min(max(playbackTime / playbackDuration, 0), 1)
    }

    private var owner: VideoOwner? {
        guard ownerMID != nil || ownerName != nil || ownerFace != nil else { return nil }
        return VideoOwner(mid: ownerMID ?? 0, name: ownerName ?? "", face: ownerFace)
    }
}

nonisolated struct StoredPlaybackProgress: Codable, Equatable {
    let bvid: String
    let cid: Int?
    let playbackTime: TimeInterval
    let playbackDuration: TimeInterval?
    let updatedAt: Date
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var appearanceMode: AppAppearanceMode
    @Published private(set) var appIconPreference: AppIconPreference
    @Published private(set) var appTintColorHex: String
    @Published private(set) var followsSystemFontSize: Bool
    @Published private(set) var manualFontSize: AppManualFontSize
    @Published private(set) var defaultPlaybackRate: Double
    @Published private(set) var playbackHistorySyncThresholdSeconds: Int
    @Published private(set) var preferredVideoQuality: Int?
    @Published private(set) var cellularPreferredVideoQuality: Int?
    @Published private(set) var playbackAutoOptimizationMode: PlaybackAutoOptimizationMode
    @Published private(set) var playbackStreamSourcePreference: PlaybackStreamSourcePreference
    @Published private(set) var videoCodecPreference: VideoCodecPreference
    @Published private(set) var forceHardwareDecodeEnabled: Bool
    @Published private(set) var dolbyVisionRenderingPolicy: DolbyVisionRenderingPolicy
    @Published private(set) var playbackCDNPreference: PlaybackCDNPreference
    @Published private(set) var playbackCustomCDNHost: String?
    @Published private(set) var playbackCDNProbeRefreshPolicy: PlaybackCDNProbeRefreshPolicy
    @Published private(set) var playbackCDNProbeRefreshIntervalMinutes: Int
    @Published private(set) var playbackNetworkAddressFamilyPreference: PlaybackNetworkAddressFamilyPreference
    @Published private(set) var prefersBackupAudioURL: Bool
    @Published private(set) var playbackCDNProbeSnapshot: PlaybackCDNProbeSnapshot?
    @Published private(set) var blocksAdDynamics: Bool
    @Published private(set) var blocksGoodsDynamics: Bool
    @Published private(set) var blocksGoodsComments: Bool
    @Published private(set) var blockedDynamicKeywords: [String]
    @Published private(set) var recommendMinimumDurationSeconds: Int
    @Published private(set) var recommendMinimumViewCount: Int
    @Published private(set) var recommendMinimumLikeRatioPercent: Int
    @Published private(set) var blockedRecommendKeywords: [String]
    @Published private(set) var appliesRecommendFiltersToRelatedVideos: Bool
    @Published private(set) var danmakuEnabled: Bool
    @Published private(set) var danmakuSettings: DanmakuSettings
    @Published private(set) var sponsorBlockEnabled: Bool
    @Published private(set) var pictureInPictureEnabled: Bool
    @Published private(set) var playerPerformanceOverlayEnabled: Bool
    @Published private(set) var resourceLoadingResumePacketWarmupEnabled: Bool
    @Published private(set) var playbackPlayableFallbackDeadlineExperimentEnabled: Bool
    @Published private(set) var videoRotationFrameReportOverlayEnabled: Bool
    @Published private(set) var videoDetailNavigationLatencyDiagnosticsEnabled: Bool
    @Published private(set) var playerControlEdgeScrimEnabled: Bool
    @Published private(set) var showsVideoDetailNetworkDiagnosticsButton: Bool
    @Published private(set) var showsVideoDetailPinnedProgressBar: Bool
    @Published private(set) var videoDetailAutoplayEnabled: Bool
    @Published private(set) var videoListenPlaybackOrder: VideoListenPlaybackOrder
    @Published private(set) var videoListenPlaylistSortOrder: VideoListenPlaylistSortOrder
    @Published private(set) var cellularBiliTrafficCompatibilityExperimentEnabled: Bool
    @Published private(set) var incognitoModeEnabled: Bool
    @Published private(set) var guestModeEnabled: Bool
    @Published private(set) var multiAccountExperimentEnabled: Bool
    @Published private(set) var dynamicCommentHitAreaVisualizationExperimentEnabled: Bool
    @Published private(set) var nativePullRefreshEnabled: Bool
    @Published private(set) var minimizesTabBarOnScroll: Bool
    @Published private(set) var videoDetailSegmentedPickerGlassStyle: VideoDetailSegmentedPickerGlassStyle
    @Published private(set) var liquidGlassStylePreference: AppLiquidGlassStylePreference
    @Published private(set) var remoteImageQualityPreference: RemoteImageQualityPreference
    @Published private(set) var videoCoverBadgeShadowOpacity: Double
    @Published private(set) var videoCoverBottomScrimEnabled: Bool
    @Published private(set) var showsVideoCoverDurationBadges: Bool
    @Published private(set) var remoteImageDiagnosticsEnabled: Bool
    @Published private(set) var force120HzScrollingEnabled: Bool
    @Published private(set) var visibleRootTabs: [AppTab]
    @Published private(set) var homeRefreshTriggerDistance: Double
    @Published private(set) var homeFeedLayout: HomeFeedLayout
    @Published private(set) var homeRecommendFeedSourcePreference: HomeRecommendFeedSourcePreference
    @Published private(set) var showsHotSearches: Bool

    private let userDefaults: UserDefaults
    private static let appearanceModeKey = "cc.bili.appearance.mode.v1"
    private static let appIconPreferenceKey = "cc.bili.appearance.appIconPreference.v1"
    private static let appTintColorHexKey = "cc.bili.appearance.tintColorHex.v1"
    private static let followsSystemFontSizeKey = "cc.bili.appearance.followsSystemFontSize.v1"
    private static let manualFontSizeKey = "cc.bili.appearance.manualFontSize.v1"
    private static let appTintColorDefaultMigrationKey = "cc.bili.appearance.tintColorDefaultPinkMigration.v1"
    private static let appTintColorDefaultToneMigrationKey = "cc.bili.appearance.tintColorDefaultToneMigration.v2"
    private static let appTintColorPreviousDefaultMigrationKey =
        "cc.bili.appearance.tintColorPreviousDefaultMigration.v3"
    private static let defaultPlaybackRateKey = "cc.bili.playback.defaultPlaybackRate.v1"
    private static let playbackHistorySyncThresholdSecondsKey = "cc.bili.playback.historySyncThresholdSeconds.v1"
    private static let preferredVideoQualityKey = "cc.bili.playback.preferredVideoQuality.v1"
    private static let cellularPreferredVideoQualityKey = "cc.bili.playback.cellularPreferredVideoQuality.v1"
    private static let playbackAutoOptimizationModeKey = "cc.bili.playback.autoOptimizationMode.v1"
    private static let playbackStreamSourcePreferenceKey = "cc.bili.playback.streamSourcePreference.v1"
    private static let videoCodecPreferenceKey = VideoCodecPreference.storageKey
    private static let forceHardwareDecodeKey = PlaybackHardwareDecodePolicy.storageKey
    private static let dolbyVisionRenderingPolicyKey = DolbyVisionRenderingPolicy.storageKey
    private static let playbackCDNPreferenceKey = "cc.bili.playback.cdnPreference.v1"
    private static let playbackCustomCDNHostKey = PlaybackCDNPreference.customHostStorageKey
    private static let playbackCDNProbeRefreshPolicyKey = "cc.bili.playback.cdnProbeRefreshPolicy.v1"
    private static let playbackCDNProbeRefreshIntervalMinutesKey = "cc.bili.playback.cdnProbeRefreshIntervalMinutes.v1"
    private static let playbackNetworkAddressFamilyPreferenceKey = "cc.bili.playback.networkAddressFamilyPreference.v1"
    private static let prefersBackupAudioURLKey = PlaybackAudioURLPolicy.storageKey
    private static let playbackCDNProbeSnapshotKey = "cc.bili.playback.cdnProbeSnapshot.v1"
    private static let playbackCDNProbeSnapshotsByContextKey = "cc.bili.playback.cdnProbeSnapshotsByContext.v1"
    private static let playbackProgressByBVIDKey = "cc.bili.playback.progressByBVID.v1"
    private static let blocksAdDynamicsKey = "cc.bili.content.blocksAdDynamics.v1"
    private static let blocksGoodsDynamicsKey = "cc.bili.content.blocksGoodsDynamics.v1"
    private static let blocksGoodsCommentsKey = "cc.bili.content.blocksGoodsComments.v1"
    private static let blockedDynamicKeywordsKey = "cc.bili.content.blockedDynamicKeywords.v1"
    private static let recommendMinimumDurationSecondsKey = "cc.bili.content.recommendMinimumDurationSeconds.v1"
    private static let recommendMinimumViewCountKey = "cc.bili.content.recommendMinimumViewCount.v1"
    private static let recommendMinimumLikeRatioPercentKey = "cc.bili.content.recommendMinimumLikeRatioPercent.v1"
    private static let blockedRecommendKeywordsKey = "cc.bili.content.blockedRecommendKeywords.v1"
    private static let appliesRecommendFiltersToRelatedVideosKey =
        "cc.bili.content.appliesRecommendFiltersToRelatedVideos.v1"
    private static let danmakuEnabledKey = "cc.bili.playback.danmakuEnabled.v1"
    private static let danmakuSettingsKey = "cc.bili.playback.danmakuSettings.v1"
    private static let sponsorBlockEnabledKey = "cc.bili.playback.sponsorBlockEnabled.v1"
    private static let pictureInPictureEnabledKey = "cc.bili.playback.pictureInPictureEnabled.v1"
    private static let playerPerformanceOverlayEnabledKey = "cc.bili.playback.performanceOverlayEnabled.v1"
    private static let resourceLoadingResumePacketWarmupEnabledKey = ResourceLoadingExperiment.Feature
        .resumePacketWarmup.storageKey
    private static let playbackPlayableFallbackDeadlineExperimentEnabledKey =
        PlayableFallbackDeadlineExperiment.storageKey
    private static let videoRotationFrameReportOverlayEnabledKey =
        "cc.bili.playback.rotationFrameReportOverlayEnabled.v1"
    private static let videoDetailNavigationLatencyDiagnosticsEnabledKey =
        "cc.bili.videoDetail.navigationLatencyDiagnosticsEnabled.v1"
    nonisolated static let playerControlEdgeScrimEnabledKey = "cc.bili.playback.controlEdgeScrimEnabled.v1"
    private static let legacyPlayerIconOnlyControlsExperimentEnabledKey =
        "cc.bili.playback.iconOnlyControlsExperimentEnabled.v1"
    private static let legacyPlayerFullscreenStatusExperimentEnabledKey =
        "cc.bili.playback.fullscreenStatusExperimentEnabled.v1"
    private static let showsVideoDetailNetworkDiagnosticsButtonKey =
        "cc.bili.videoDetail.showsNetworkDiagnosticsButton.v1"
    private static let showsVideoDetailPinnedProgressBarKey = "cc.bili.videoDetail.showsPinnedProgressBar.v1"
    private static let videoDetailAutoplayEnabledKey = "cc.bili.videoDetail.autoplayEnabled.v1"
    private static let videoListenPlaybackOrderKey = "cc.bili.playback.videoListenPlaybackOrder.v1"
    private static let videoListenPlaylistSortOrderKey = "cc.bili.playback.videoListenPlaylistSortOrder.v1"
    private static let cellularBiliTrafficCompatibilityExperimentEnabledKey = CellularBiliTrafficCompatibilityExperiment
        .storageKey
    private static let incognitoModeEnabledKey = "cc.bili.privacy.incognitoModeEnabled.v1"
    private static let guestModeEnabledKey = "cc.bili.privacy.guestModeEnabled.v1"
    private static let multiAccountExperimentEnabledKey = "cc.bili.account.multiAccountExperimentEnabled.v1"
    private static let dynamicCommentHitAreaVisualizationExperimentEnabledKey =
        "cc.bili.experimental.dynamicCommentHitAreaVisualization.v1"
    private static let nativePullRefreshEnabledKey =
        "cc.bili.home.nativePullRefreshEnabled.v1"
    private static let legacyUnifiedPullRefreshIndicatorExperimentEnabledKey =
        "cc.bili.pullRefresh.unifiedDetailStyleExperimentEnabled.v1"
    private static let minimizesTabBarOnScrollKey = "cc.bili.display.minimizesTabBarOnScroll.v1"
    private static let videoDetailSegmentedPickerGlassStyleKey =
        "cc.bili.videoDetail.segmentedPickerGlassStyle.v1"
    private static let liquidGlassStylePreferenceKey = AppLiquidGlassStylePreference.storageKey
    private static let remoteImageQualityPreferenceKey = RemoteImageQualityPreference.storageKey
    private static let videoCoverBadgeShadowOpacityKey = VideoCoverBadgeShadow.storageKey
    private static let videoCoverBottomScrimEnabledKey = VideoCoverBottomScrimSettings.storageKey
    private static let videoCoverDurationBadgesEnabledKey = VideoCoverDurationBadgeSettings.storageKey
    private static let retiredExperimentKeys = [
        "cc.bili.experimental.videoDetailToolbarCommentComposer.v1",
        "cc.bili.experimental.commentSheetPrimaryAuthorName.v1",
        "cc.bili.experimental.scrollableTabHeaders.v1",
        "cc.bili.display.rootNavigationContainerExperimentEnabled.v1",
        "cc.bili.display.rootTabBarTransitionCoordinationExperimentEnabled.v1",
        "cc.bili.display.officialDestinationTabBarVisibilityExperimentEnabled.v1",
        "cc.bili.videoDetail.sharedSystemTabBarExperimentEnabled.v1",
        "cc.bili.display.singleOwnerTabBarExperimentEnabled.v1",
        "cc.bili.videoDetail.systemBottomBarExperimentEnabled.v1",
        "cc.bili.display.softPrimaryPageTopEdgeEffectExperimentEnabled.v1",
        "cc.bili.display.scrollEdgeEffectPreference.v1",
        "cc.bili.display.nativeTypographyRefinementExperimentEnabled.v1",
        "cc.bili.experimental.dynamicBodySystemStyle.v1",
        "cc.bili.experimental.dynamicFeedLargeTypography.v1",
        "cc.bili.experimental.systemTextStyle.v1",
        "cc.bili.experimental.dynamicFeedAccurateExpansion.v1",
        "cc.bili.experimental.dynamicFeedPiliPlusLineSpacing.v1",
        "cc.bili.experimental.dynamicDetailCommentSpacing.v1",
        "cc.bili.experimental.dynamicDetailBottomInteractionBarExperimentEnabled.v1",
        "cc.bili.experimental.dynamicDetailComposer.v1",
        "cc.bili.display.richCommentComposerExperimentEnabled.v1",
        "cc.bili.experimental.dynamicDetailTelegramInputStyle.v1",
        "cc.bili.experimental.keyboardAnchoredCommentPhotoPickerExperimentEnabled.v1",
        "cc.bili.experimental.keyboardAnchoredCommentEmotePickerExperimentEnabled.v1",
        "cc.bili.experimental.scrollMinimizingTabBar.v1",
        "cc.bili.experimental.videoDetailInteractiveScrollCollapse.v1",
        "cc.bili.experimental.videoDetailInitialAspectRatio.v1",
        "cc.bili.videoDetail.segmentedPickerExperimentEnabled.v1",
        "cc.bili.videoDetail.segmentedPickerSelectionFill.v1",
        "cc.bili.experimental.videoDetailToolbarSegmentedPicker.v1",
        "cc.bili.experimental.videoDetailToolbarCommentComposer.v1",
        "cc.bili.experimental.commentSheetPrimaryAuthorName.v1",
        "cc.bili.home.navigationModeSwitcherExperimentEnabled.v1",
        "cc.bili.home.navigationToolbarScrollVisibilityExperimentEnabled.v1",
        "cc.bili.home.navigationChromeDelayedReturnExperimentEnabled.v1",
        "cc.bili.home.navigationChromeUnifiedScrollVisibilityExperimentEnabled.v1",
        "cc.bili.home.navigationModeTitleTransitionExperimentEnabled.v1",
        "cc.bili.home.feedWarmupExperimentEnabled.v1",
        "cc.bili.dynamic.feedWarmupExperimentEnabled.v1",
        "cc.bili.network.pathStabilizationExperimentEnabled.v1",
        "cc.bili.dynamic.detailKeepsTabBarVisibleExperimentEnabled.v1",
        "cc.bili.dynamic.nativeNavigationTitleExperimentEnabled.v1",
        "cc.bili.playback.startupRequestSchedulingExperimentEnabled.v1",
        "cc.bili.live.videoDetailLayoutExperimentEnabled.v1",
        "cc.bili.live.piliPodLayoutExperimentEnabled.v1",
        "cc.bili.live.parallelStartupExperimentEnabled.v1",
        "cc.bili.live.adaptiveCDNStartupExperimentEnabled.v1",
        "cc.bili.live.slowStartupRouteSwitchExperimentEnabled.v1",
        "cc.bili.live.hlsFastStartExperimentEnabled.v1",
        "cc.bili.live.danmakuRenderBatchingExperimentEnabled.v1",
        "cc.bili.live.rotationSurfaceAlignmentExperimentEnabled.v1",
        "cc.bili.display.mineSingleStackNavigationExperimentEnabled.v1",
        "cc.bili.display.fixedVideoTitleTypographyExperimentEnabled.v1",
        "cc.bili.display.unifiedAppTypographyExperimentEnabled.v1",
        "cc.bili.display.highQualityImageViewerExperimentEnabled.v1",
        "cc.bili.display.imageViewerGestureUpgradeExperimentEnabled.v1",
        "cc.bili.account.messageCenterExperimentEnabled.v1",
        "cc.bili.display.telegramTopEdgeBlurExperimentEnabled.v1",
        "cc.bili.display.uploaderProfileGlassSheetExperimentEnabled.v1",
        "cc.bili.display.uploaderProfileGlassSheetExperimentEnabled.v2",
        "cc.bili.videoDetail.directUIKitSurfaceExperimentEnabled.v1",
        "cc.bili.live.simpleLiveRoomLayoutExperimentEnabled.v1",
        "cc.bili.playback.videoListenModeExperimentEnabled.v1",
        "cc.bili.playback.officialListenerPlaylistExperimentEnabled.v1",
        "cc.bili.playback.metalDanmakuRendererExperimentEnabled.v1",
        "cc.bili.videoDetail.moreControlsSwiftUISheetExperimentEnabled.v1",
        "cc.bili.playback.nativePlayerProgressSliderExperimentEnabled.v1",
        "cc.bili.playback.iosNativePlaybackControlsExperimentEnabled.v1",
        "cc.bili.display.unifiedVideoCoverBorderExperimentEnabled.v1",
        "cc.bili.display.thumbnailLongPressPreviewExperimentEnabled.v1",
        "cc.bili.display.fastScrollImageLoadSuppressionExperimentEnabled.v1",
        "cc.bili.display.remoteImageCDNFailoverExperimentEnabled.v1",
        "cc.bili.home.nativePullRefreshIndicatorExperimentEnabled.v1",
        "cc.bili.videoDetail.rotationOptimizationExperimentEnabled.v1",
        "cc.bili.playback.diagnosticsBackgroundProcessingExperimentEnabled.v1",
        "cc.bili.playback.avPlayerStartupPathOptimizationExperimentEnabled.v1",
        "cc.bili.playback.piliPlusStylePlayURLSelectionExperimentEnabled.v1",
        "cc.bili.resourceLoading.experimentEnabled.v1",
        "cc.bili.resourceLoading.firstScreenPriorityExperimentEnabled.v1",
        "cc.bili.resourceLoading.visibleImagePriorityExperimentEnabled.v1",
        "cc.bili.resourceLoading.readRequestCoalescingExperimentEnabled.v1",
        "cc.bili.resourceLoading.dynamicDiskSnapshotExperimentEnabled.v1",
        "cc.bili.playback.immediatePlayerCreationExperimentEnabled.v1",
        "cc.bili.videoDetail.transitionStabilityExperimentEnabled.v1",
        "cc.bili.videoDetail.backgroundRenderFreezeExperimentEnabled.v1",
        "cc.bili.videoDetail.deferredSecondaryContentExperimentEnabled.v1",
        "cc.bili.videoDetail.fastNavigationExperimentEnabled.v1",
        "cc.bili.videoDetail.shortNavigationTransitionExperimentEnabled.v1",
        "cc.bili.dynamic.commentReadingExperimentEnabled.v1",
        "cc.bili.dynamic.commentSortPreference.v1",
        "cc.bili.dynamic.commentPublishExperimentEnabled.v1",
        "cc.bili.dynamic.commentReplyPublishExperimentEnabled.v1",
        "cc.bili.dynamic.realLikeExperimentEnabled.v1",
        "cc.bili.comment.likeExperimentEnabled.v1",
        "cc.bili.dynamic.imageTextDetailExperimentEnabled.v1",
        "cc.bili.home.navigationBarScrollVisibilityExperimentEnabled.v2",
        "cc.bili.home.navigationTitleHideDistanceExperimentEnabled.v1",
        "cc.bili.home.navigationTitleHideDistance.v1",
        "cc.bili.search.tabExpansionExperimentEnabled.v1",
        "cc.bili.playback.relatedEarlyPlayURLPrefetchExperimentEnabled.v1",
        "cc.bili.playback.relatedStartupPackageWarmupExperimentEnabled.v1",
        legacyUnifiedPullRefreshIndicatorExperimentEnabledKey,
        legacyPlayerIconOnlyControlsExperimentEnabledKey,
        legacyPlayerFullscreenStatusExperimentEnabledKey,
    ]
    private static let remoteImageDiagnosticsEnabledKey = RemoteImageDiagnosticsSettings.storageKey
    private static let force120HzScrollingEnabledKey = RefreshRateManager.isEnabledKey
    private static let visibleRootTabsKey = "cc.bili.display.visibleRootTabs.v1"
    private static let homeRefreshTriggerDistanceKey = "cc.bili.home.refreshTriggerDistance.v1"
    private static let homeFeedLayoutKey = "cc.bili.home.feedLayout.v1"
    private static let homeRecommendFeedSourcePreferenceKey = "cc.bili.home.recommendFeedSourcePreference.v1"
    private static let showsHotSearchesKey = "cc.bili.search.showsHotSearches.v1"
    private static let supportedPlaybackRates = [0.75, 1.0, 1.25, 1.5, 2.0]
    nonisolated static let defaultPreferredVideoQuality = 112
    nonisolated static let defaultCellularPreferredVideoQuality = 64
    nonisolated static let defaultAppTintColorHex = AppThemeTintColor.defaultHex
    nonisolated static let defaultPlaybackStreamSourcePreference: PlaybackStreamSourcePreference = .app
    nonisolated static let defaultHomeRecommendFeedSourcePreference: HomeRecommendFeedSourcePreference = .app
    nonisolated static let defaultHomeFeedLayout: HomeFeedLayout = .singleColumn
    nonisolated static let defaultPlaybackHistorySyncThresholdSeconds = 5
    nonisolated static let supportedPlaybackHistorySyncThresholdSeconds = [5, 10, 30]
    nonisolated static let supportedVideoQualities = BiliVideoQuality.supportedQualities
    nonisolated static let playbackCDNProbeRefreshIntervalRange: ClosedRange<Int> = 15...1440
    nonisolated static let defaultPlaybackCDNProbeRefreshIntervalMinutes = 1440
    nonisolated static let homeRefreshDistanceRange: ClosedRange<Double> = 70...180
    nonisolated static let defaultHomeRefreshTriggerDistance = 110.0
    nonisolated static let supportedRecommendMinimumDurations = [0, 30, 60, 90, 120]
    nonisolated static let supportedRecommendMinimumViews = [0, 50, 100, 500, 1000]
    nonisolated static let supportedRecommendMinimumLikeRatios = [0, 1, 2, 3, 4]
    private static let temporaryPlaybackCDNAvoidanceDuration: TimeInterval = 10 * 60
    private static let maxStoredPlaybackProgressCount = 240
    private var playbackCDNProbeSnapshotsByContext: [String: PlaybackCDNProbeSnapshot] = [:]
    private var temporarilyAvoidedPlaybackCDNPreferences: [PlaybackCDNPreference: Date] = [:]
    private var playbackProgressByBVID: [String: StoredPlaybackProgress] = [:]

    var effectivePlaybackCDNPreference: PlaybackCDNPreference {
        effectivePlaybackCDNPreference(for: playbackCDNPreference)
    }

    var effectivePreferredVideoQuality: Int? {
        effectivePreferredVideoQuality(for: PlaybackEnvironment.current.networkClass)
    }

    var isPlaybackAutoOptimizationEnabled: Bool {
        playbackAutoOptimizationMode.isEnabled
    }

    var automaticPlaybackCDNRecommendation: PlaybackCDNPreference? {
        playbackCDNRecommendation(allowExpired: true)
    }

    var activePlaybackCDNAvoidanceDescription: String? {
        let now = Date()
        let activeAvoidances =
            temporarilyAvoidedPlaybackCDNPreferences
            .filter { $0.value > now }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                return lhs.key.title < rhs.key.title
            }
        guard !activeAvoidances.isEmpty else { return nil }
        return
            activeAvoidances
            .map { preference, expiresAt in
                "\(preference.title) 至 \(expiresAt.formatted(date: .omitted, time: .shortened))"
            }
            .joined(separator: "、")
    }

    var playbackCDNProbeSnapshotForCurrentContext: PlaybackCDNProbeSnapshot? {
        playbackCDNProbeSnapshotsByContext[currentPlaybackCDNProbeContextKey]
    }

    var appTintColor: Color {
        AppThemeTintColor.color(for: appTintColorHex)
    }

    var needsPlaybackCDNProbeRefresh: Bool {
        guard playbackCDNPreference == .automatic else { return false }
        guard let snapshot = playbackCDNProbeSnapshotForCurrentContext else { return true }
        if snapshot.isExpired(freshnessInterval: playbackCDNProbeRefreshInterval) { return true }
        if snapshot.recommendedPreference == nil,
            snapshot.isExpired(freshnessInterval: 15 * 60)
        {
            return true
        }
        return false
    }

    var playbackCDNProbeRefreshInterval: TimeInterval {
        TimeInterval(playbackCDNProbeRefreshIntervalMinutes * 60)
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.appearanceMode =
            AppAppearanceMode(
                rawValue: userDefaults.string(forKey: Self.appearanceModeKey) ?? ""
            ) ?? .system
        self.appIconPreference =
            AppIconPreference(
                rawValue: userDefaults.string(forKey: Self.appIconPreferenceKey) ?? ""
            ) ?? .system
        self.followsSystemFontSize =
            userDefaults.object(
                forKey: Self.followsSystemFontSizeKey
            ) as? Bool ?? true
        self.manualFontSize =
            (userDefaults.object(forKey: Self.manualFontSizeKey) as? Int)
            .flatMap(AppManualFontSize.init(rawValue:)) ?? .defaultValue
        let storedAppTintColorHex = AppThemeTintColor.normalizedHex(
            userDefaults.string(forKey: Self.appTintColorHexKey)
        )
        let hasMigratedLegacyAppTintDefaults = userDefaults.bool(
            forKey: Self.appTintColorDefaultToneMigrationKey
        )
        let hasMigratedPreviousAppTintDefault = userDefaults.bool(
            forKey: Self.appTintColorPreviousDefaultMigrationKey
        )
        if let storedAppTintColorHex,
            !hasMigratedLegacyAppTintDefaults,
            AppThemeTintColor.legacyDefaultHexes.contains(storedAppTintColorHex)
        {
            self.appTintColorHex = Self.defaultAppTintColorHex
            userDefaults.set(Self.defaultAppTintColorHex, forKey: Self.appTintColorHexKey)
        } else if let storedAppTintColorHex,
            !hasMigratedPreviousAppTintDefault,
            storedAppTintColorHex == AppThemeTintColor.previousDefaultHex
        {
            self.appTintColorHex = Self.defaultAppTintColorHex
            userDefaults.set(Self.defaultAppTintColorHex, forKey: Self.appTintColorHexKey)
        } else {
            self.appTintColorHex = storedAppTintColorHex ?? Self.defaultAppTintColorHex
        }
        userDefaults.set(true, forKey: Self.appTintColorDefaultToneMigrationKey)
        userDefaults.set(true, forKey: Self.appTintColorPreviousDefaultMigrationKey)
        userDefaults.set(true, forKey: Self.appTintColorDefaultMigrationKey)
        self.defaultPlaybackRate = Self.normalizedPlaybackRate(
            userDefaults.object(forKey: Self.defaultPlaybackRateKey) as? Double ?? 1.0)
        self.playbackHistorySyncThresholdSeconds = Self.normalizedPlaybackHistorySyncThresholdSeconds(
            userDefaults.object(forKey: Self.playbackHistorySyncThresholdSecondsKey) as? Int
                ?? Self.defaultPlaybackHistorySyncThresholdSeconds
        )
        if let storedVideoQuality = userDefaults.object(forKey: Self.preferredVideoQualityKey) as? Int {
            self.preferredVideoQuality = storedVideoQuality == 0 ? nil : Self.normalizedVideoQuality(storedVideoQuality)
        } else {
            self.preferredVideoQuality = Self.defaultPreferredVideoQuality
        }
        if let storedCellularVideoQuality = userDefaults.object(forKey: Self.cellularPreferredVideoQualityKey) as? Int {
            self.cellularPreferredVideoQuality =
                storedCellularVideoQuality == 0 ? nil : Self.normalizedVideoQuality(storedCellularVideoQuality)
        } else {
            self.cellularPreferredVideoQuality = Self.defaultCellularPreferredVideoQuality
        }
        self.playbackAutoOptimizationMode =
            PlaybackAutoOptimizationMode(
                rawValue: userDefaults.string(forKey: Self.playbackAutoOptimizationModeKey) ?? ""
            ) ?? .automatic
        self.playbackStreamSourcePreference =
            PlaybackStreamSourcePreference(
                rawValue: userDefaults.string(forKey: Self.playbackStreamSourcePreferenceKey) ?? ""
            ) ?? Self.defaultPlaybackStreamSourcePreference
        self.videoCodecPreference = VideoCodecPreference.stored(in: userDefaults)
        self.forceHardwareDecodeEnabled = PlaybackHardwareDecodePolicy.stored(in: userDefaults)
        self.dolbyVisionRenderingPolicy = DolbyVisionRenderingPolicy.stored(in: userDefaults)
        self.playbackCDNPreference =
            PlaybackCDNPreference(
                rawValue: userDefaults.string(forKey: Self.playbackCDNPreferenceKey) ?? ""
            ) ?? .automatic
        self.playbackCustomCDNHost = PlaybackCDNPreference.normalizedCustomHost(
            userDefaults.string(forKey: Self.playbackCustomCDNHostKey)
        )
        self.playbackCDNProbeRefreshPolicy =
            PlaybackCDNProbeRefreshPolicy(
                rawValue: userDefaults.string(forKey: Self.playbackCDNProbeRefreshPolicyKey) ?? ""
            ) ?? .interval
        self.playbackCDNProbeRefreshIntervalMinutes = Self.normalizedPlaybackCDNProbeRefreshIntervalMinutes(
            userDefaults.object(forKey: Self.playbackCDNProbeRefreshIntervalMinutesKey) as? Int
                ?? Self.defaultPlaybackCDNProbeRefreshIntervalMinutes
        )
        let storedAddressFamilyPreference =
            PlaybackNetworkAddressFamilyPreference(
                rawValue: userDefaults.string(forKey: Self.playbackNetworkAddressFamilyPreferenceKey) ?? ""
            ) ?? .automatic
        self.playbackNetworkAddressFamilyPreference = storedAddressFamilyPreference
        self.prefersBackupAudioURL = PlaybackAudioURLPolicy.stored(in: userDefaults)
        let currentProbeContextKey = Self.playbackCDNProbeContextKey(
            networkClass: PlaybackEnvironment.current.networkClass,
            addressFamilyPreference: storedAddressFamilyPreference
        )
        if let contextData = userDefaults.data(forKey: Self.playbackCDNProbeSnapshotsByContextKey),
            let snapshots = try? JSONDecoder().decode([String: PlaybackCDNProbeSnapshot].self, from: contextData)
        {
            self.playbackCDNProbeSnapshotsByContext = snapshots
            self.playbackCDNProbeSnapshot = snapshots[currentProbeContextKey]
        } else if let probeSnapshotData = userDefaults.data(forKey: Self.playbackCDNProbeSnapshotKey),
            let probeSnapshot = try? JSONDecoder().decode(PlaybackCDNProbeSnapshot.self, from: probeSnapshotData)
        {
            self.playbackCDNProbeSnapshotsByContext = [currentProbeContextKey: probeSnapshot]
            self.playbackCDNProbeSnapshot = probeSnapshot
        } else {
            self.playbackCDNProbeSnapshot = nil
        }
        if let progressData = userDefaults.data(forKey: Self.playbackProgressByBVIDKey),
            let progress = try? JSONDecoder().decode([String: StoredPlaybackProgress].self, from: progressData)
        {
            self.playbackProgressByBVID = progress
        }
        self.blocksAdDynamics = userDefaults.object(forKey: Self.blocksAdDynamicsKey) as? Bool ?? true
        self.blocksGoodsDynamics = userDefaults.object(forKey: Self.blocksGoodsDynamicsKey) as? Bool ?? true
        self.blocksGoodsComments = userDefaults.object(forKey: Self.blocksGoodsCommentsKey) as? Bool ?? true
        self.blockedDynamicKeywords = Self.normalizedBlockedDynamicKeywords(
            userDefaults.stringArray(forKey: Self.blockedDynamicKeywordsKey) ?? []
        )
        self.recommendMinimumDurationSeconds = Self.normalizedRecommendFilterValue(
            userDefaults.object(forKey: Self.recommendMinimumDurationSecondsKey) as? Int,
            supportedValues: Self.supportedRecommendMinimumDurations
        )
        self.recommendMinimumViewCount = Self.normalizedRecommendFilterValue(
            userDefaults.object(forKey: Self.recommendMinimumViewCountKey) as? Int,
            supportedValues: Self.supportedRecommendMinimumViews
        )
        self.recommendMinimumLikeRatioPercent = Self.normalizedRecommendFilterValue(
            userDefaults.object(forKey: Self.recommendMinimumLikeRatioPercentKey) as? Int,
            supportedValues: Self.supportedRecommendMinimumLikeRatios
        )
        self.blockedRecommendKeywords = Self.normalizedBlockedRecommendKeywords(
            userDefaults.stringArray(forKey: Self.blockedRecommendKeywordsKey) ?? []
        )
        self.appliesRecommendFiltersToRelatedVideos =
            userDefaults.object(forKey: Self.appliesRecommendFiltersToRelatedVideosKey) as? Bool ?? false
        self.danmakuEnabled = userDefaults.object(forKey: Self.danmakuEnabledKey) as? Bool ?? true
        if let settingsData = userDefaults.data(forKey: Self.danmakuSettingsKey),
            let settings = try? JSONDecoder().decode(DanmakuSettings.self, from: settingsData)
        {
            self.danmakuSettings = settings.normalized
        } else {
            self.danmakuSettings = .default
        }
        self.sponsorBlockEnabled = userDefaults.object(forKey: Self.sponsorBlockEnabledKey) as? Bool ?? false
        self.pictureInPictureEnabled = userDefaults.object(forKey: Self.pictureInPictureEnabledKey) as? Bool ?? false
        self.playerPerformanceOverlayEnabled =
            userDefaults.object(forKey: Self.playerPerformanceOverlayEnabledKey) as? Bool ?? false
        self.resourceLoadingResumePacketWarmupEnabled =
            userDefaults.object(
                forKey: Self.resourceLoadingResumePacketWarmupEnabledKey
            ) as? Bool ?? true
        self.playbackPlayableFallbackDeadlineExperimentEnabled =
            userDefaults.object(
                forKey: Self.playbackPlayableFallbackDeadlineExperimentEnabledKey
            ) as? Bool ?? PlayableFallbackDeadlineExperiment.defaultIsEnabled
        self.videoRotationFrameReportOverlayEnabled =
            userDefaults.object(forKey: Self.videoRotationFrameReportOverlayEnabledKey) as? Bool ?? false
        self.videoDetailNavigationLatencyDiagnosticsEnabled =
            userDefaults.object(
                forKey: Self.videoDetailNavigationLatencyDiagnosticsEnabledKey
            ) as? Bool ?? false
        self.playerControlEdgeScrimEnabled =
            userDefaults.object(forKey: Self.playerControlEdgeScrimEnabledKey) as? Bool ?? true
        self.showsVideoDetailNetworkDiagnosticsButton =
            userDefaults.object(forKey: Self.showsVideoDetailNetworkDiagnosticsButtonKey) as? Bool ?? false
        self.showsVideoDetailPinnedProgressBar =
            userDefaults.object(forKey: Self.showsVideoDetailPinnedProgressBarKey) as? Bool ?? false
        self.videoDetailAutoplayEnabled =
            Self.boolValue(forKey: Self.videoDetailAutoplayEnabledKey, in: userDefaults) ?? true
        self.videoListenPlaybackOrder =
            userDefaults.string(
                forKey: Self.videoListenPlaybackOrderKey
            ).flatMap(VideoListenPlaybackOrder.init(rawValue:)) ?? .sequential
        self.videoListenPlaylistSortOrder =
            userDefaults.string(
                forKey: Self.videoListenPlaylistSortOrderKey
            ).flatMap(VideoListenPlaylistSortOrder.init(rawValue:)) ?? .normal
        self.cellularBiliTrafficCompatibilityExperimentEnabled =
            userDefaults.object(
                forKey: Self.cellularBiliTrafficCompatibilityExperimentEnabledKey
            ) as? Bool ?? CellularBiliTrafficCompatibilityExperiment.defaultIsEnabled
        self.incognitoModeEnabled = userDefaults.object(forKey: Self.incognitoModeEnabledKey) as? Bool ?? false
        self.guestModeEnabled = userDefaults.object(forKey: Self.guestModeEnabledKey) as? Bool ?? false
        self.multiAccountExperimentEnabled =
            userDefaults.object(
                forKey: Self.multiAccountExperimentEnabledKey
            ) as? Bool ?? false
        self.dynamicCommentHitAreaVisualizationExperimentEnabled =
            userDefaults.object(
                forKey: Self.dynamicCommentHitAreaVisualizationExperimentEnabledKey
            ) as? Bool ?? false
        let storedNativePullRefreshEnabled =
            userDefaults.object(forKey: Self.nativePullRefreshEnabledKey) as? Bool
        let nativePullRefreshEnabled = storedNativePullRefreshEnabled
            ?? userDefaults.object(
                forKey: Self.legacyUnifiedPullRefreshIndicatorExperimentEnabledKey
            ) as? Bool
            ?? true
        self.nativePullRefreshEnabled = nativePullRefreshEnabled
        if storedNativePullRefreshEnabled == nil {
            userDefaults.set(nativePullRefreshEnabled, forKey: Self.nativePullRefreshEnabledKey)
        }
        self.minimizesTabBarOnScroll = userDefaults.object(forKey: Self.minimizesTabBarOnScrollKey) as? Bool ?? true
        self.videoDetailSegmentedPickerGlassStyle =
            VideoDetailSegmentedPickerGlassStyle(
                rawValue: userDefaults.string(
                    forKey: Self.videoDetailSegmentedPickerGlassStyleKey
                ) ?? ""
            ) ?? .clear
        self.liquidGlassStylePreference = AppLiquidGlassStylePreference(
            storedRawValue: userDefaults.string(forKey: Self.liquidGlassStylePreferenceKey)
        )
        self.remoteImageQualityPreference = RemoteImageQualityPreference.stored(in: userDefaults)
        self.videoCoverBadgeShadowOpacity = VideoCoverBadgeShadow.normalized(
            userDefaults.object(forKey: Self.videoCoverBadgeShadowOpacityKey) as? Double
                ?? VideoCoverBadgeShadow.defaultOpacity
        )
        self.videoCoverBottomScrimEnabled =
            userDefaults.object(forKey: Self.videoCoverBottomScrimEnabledKey) as? Bool
            ?? VideoCoverBottomScrimSettings.defaultIsEnabled
        self.showsVideoCoverDurationBadges =
            userDefaults.object(forKey: Self.videoCoverDurationBadgesEnabledKey) as? Bool
            ?? VideoCoverDurationBadgeSettings.defaultIsEnabled
        Self.retiredExperimentKeys.forEach(userDefaults.removeObject(forKey:))
        self.remoteImageDiagnosticsEnabled =
            userDefaults.object(
                forKey: Self.remoteImageDiagnosticsEnabledKey
            ) as? Bool ?? RemoteImageDiagnosticsSettings.defaultIsEnabled
        self.force120HzScrollingEnabled =
            userDefaults.object(forKey: Self.force120HzScrollingEnabledKey) as? Bool ?? false
        self.visibleRootTabs = Self.normalizedVisibleRootTabs(
            userDefaults.stringArray(forKey: Self.visibleRootTabsKey)
        )
        self.homeRefreshTriggerDistance = Self.normalizedHomeRefreshDistance(
            userDefaults.object(forKey: Self.homeRefreshTriggerDistanceKey) as? Double
                ?? Self.defaultHomeRefreshTriggerDistance
        )
        self.homeFeedLayout =
            HomeFeedLayout(
                rawValue: userDefaults.string(forKey: Self.homeFeedLayoutKey) ?? ""
            ) ?? Self.defaultHomeFeedLayout
        self.homeRecommendFeedSourcePreference =
            HomeRecommendFeedSourcePreference(
                rawValue: userDefaults.string(forKey: Self.homeRecommendFeedSourcePreferenceKey) ?? ""
            ) ?? Self.defaultHomeRecommendFeedSourcePreference
        self.showsHotSearches = userDefaults.object(forKey: Self.showsHotSearchesKey) as? Bool ?? true
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        appearanceMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.appearanceModeKey)
    }

    func setAppIconPreference(_ preference: AppIconPreference) {
        appIconPreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.appIconPreferenceKey)
    }

    func setFollowsSystemFontSize(_ followsSystem: Bool) {
        followsSystemFontSize = followsSystem
        userDefaults.set(followsSystem, forKey: Self.followsSystemFontSizeKey)
    }

    func setManualFontSize(_ size: AppManualFontSize) {
        manualFontSize = size
        userDefaults.set(size.rawValue, forKey: Self.manualFontSizeKey)
    }

    @discardableResult
    func setAppTintColorHex(_ hex: String) -> Bool {
        guard let normalizedHex = AppThemeTintColor.normalizedHex(hex) else { return false }
        appTintColorHex = normalizedHex
        userDefaults.set(normalizedHex, forKey: Self.appTintColorHexKey)
        return true
    }

    func setAppTintColor(_ color: Color) {
        guard let hex = AppThemeTintColor.hexString(from: color) else { return }
        setAppTintColorHex(hex)
    }

    func resetAppTintColor() {
        setAppTintColorHex(Self.defaultAppTintColorHex)
    }

    func setDefaultPlaybackRate(_ rate: Double) {
        let normalizedRate = Self.normalizedPlaybackRate(rate)
        defaultPlaybackRate = normalizedRate
        userDefaults.set(normalizedRate, forKey: Self.defaultPlaybackRateKey)
    }

    func setPlaybackHistorySyncThresholdSeconds(_ seconds: Int) {
        let normalizedSeconds = Self.normalizedPlaybackHistorySyncThresholdSeconds(seconds)
        playbackHistorySyncThresholdSeconds = normalizedSeconds
        userDefaults.set(normalizedSeconds, forKey: Self.playbackHistorySyncThresholdSecondsKey)
    }

    func recordPlaybackProgress(
        video: VideoItem,
        cid: Int?,
        progress: TimeInterval,
        duration: TimeInterval?
    ) {
        let bvid = video.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bvid.isEmpty,
            progress.isFinite,
            progress >= TimeInterval(playbackHistorySyncThresholdSeconds)
        else { return }
        playbackProgressByBVID[bvid] = StoredPlaybackProgress(
            bvid: bvid,
            cid: cid ?? video.cid,
            playbackTime: progress,
            playbackDuration: duration,
            updatedAt: Date()
        )
        persistPlaybackProgress()
    }

    func localPlaybackResumeTime(
        for video: VideoItem,
        cid: Int?,
        duration: TimeInterval?
    ) -> TimeInterval? {
        guard let progress = localPlaybackProgress(for: video, duration: duration) else { return nil }
        if let progressCID = progress.cid,
            let cid,
            progressCID != cid
        {
            return nil
        }
        return progress.playbackTime
    }

    func localPlaybackProgress(
        for video: VideoItem,
        duration: TimeInterval?
    ) -> StoredPlaybackProgress? {
        guard !incognitoModeEnabled else { return nil }
        let bvid = video.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bvid.isEmpty,
            let progress = playbackProgressByBVID[bvid],
            isUsablePlaybackProgress(progress, duration: duration)
        else { return nil }
        return progress
    }

    private func isUsablePlaybackProgress(
        _ progress: StoredPlaybackProgress,
        duration: TimeInterval?
    ) -> Bool {
        guard progress.playbackTime.isFinite,
            progress.playbackTime >= TimeInterval(playbackHistorySyncThresholdSeconds)
        else { return false }
        let resolvedDuration = duration ?? progress.playbackDuration
        if let resolvedDuration, resolvedDuration > 0 {
            let remaining = resolvedDuration - progress.playbackTime
            guard remaining > 15, progress.playbackTime / resolvedDuration < 0.96 else { return false }
        }
        return true
    }

    func setPreferredVideoQuality(_ quality: Int?) {
        let normalizedQuality = Self.normalizedVideoQuality(quality)
        preferredVideoQuality = normalizedQuality
        if let normalizedQuality {
            userDefaults.set(normalizedQuality, forKey: Self.preferredVideoQualityKey)
        } else {
            userDefaults.set(0, forKey: Self.preferredVideoQualityKey)
        }
    }

    func setCellularPreferredVideoQuality(_ quality: Int?) {
        let normalizedQuality = Self.normalizedVideoQuality(quality)
        cellularPreferredVideoQuality = normalizedQuality
        if let normalizedQuality {
            userDefaults.set(normalizedQuality, forKey: Self.cellularPreferredVideoQualityKey)
        } else {
            userDefaults.set(0, forKey: Self.cellularPreferredVideoQualityKey)
        }
    }

    func setPlaybackAutoOptimizationMode(_ mode: PlaybackAutoOptimizationMode) {
        playbackAutoOptimizationMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.playbackAutoOptimizationModeKey)
    }

    func setPlaybackStreamSourcePreference(_ preference: PlaybackStreamSourcePreference) {
        playbackStreamSourcePreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.playbackStreamSourcePreferenceKey)
    }

    func setVideoCodecPreference(_ preference: VideoCodecPreference) {
        let resolvedPreference = preference.resolvedForCurrentDevice
        videoCodecPreference = resolvedPreference
        userDefaults.set(resolvedPreference.rawValue, forKey: Self.videoCodecPreferenceKey)
        PlayerSettings.shared.reload()
    }

    func setForceHardwareDecodeEnabled(_ isEnabled: Bool) {
        forceHardwareDecodeEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.forceHardwareDecodeKey)
        PlayerSettings.shared.reload()
    }

    func setDolbyVisionRenderingPolicy(_ policy: DolbyVisionRenderingPolicy) {
        dolbyVisionRenderingPolicy = policy
        userDefaults.set(policy.rawValue, forKey: Self.dolbyVisionRenderingPolicyKey)
        PlayerSettings.shared.reload()
    }

    func setHomeRecommendFeedSourcePreference(_ preference: HomeRecommendFeedSourcePreference) {
        homeRecommendFeedSourcePreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.homeRecommendFeedSourcePreferenceKey)
    }

    func setPlaybackCDNPreference(_ preference: PlaybackCDNPreference) {
        playbackCDNPreference = preference
        clearTemporaryPlaybackCDNAvoidance()
        userDefaults.set(preference.rawValue, forKey: Self.playbackCDNPreferenceKey)
    }

    func setPlaybackCustomCDNHost(_ host: String?) {
        let normalizedHost = PlaybackCDNPreference.normalizedCustomHost(host)
        guard playbackCustomCDNHost != normalizedHost else { return }
        playbackCustomCDNHost = normalizedHost
        clearTemporaryPlaybackCDNAvoidance()
        clearPlaybackCDNProbeSnapshots()
        if let normalizedHost {
            userDefaults.set(normalizedHost, forKey: Self.playbackCustomCDNHostKey)
        } else {
            userDefaults.removeObject(forKey: Self.playbackCustomCDNHostKey)
        }
    }

    func setPlaybackCDNProbeRefreshPolicy(_ policy: PlaybackCDNProbeRefreshPolicy) {
        playbackCDNProbeRefreshPolicy = policy
        userDefaults.set(policy.rawValue, forKey: Self.playbackCDNProbeRefreshPolicyKey)
    }

    func setPlaybackCDNProbeRefreshIntervalMinutes(_ minutes: Int) {
        let normalizedMinutes = Self.normalizedPlaybackCDNProbeRefreshIntervalMinutes(minutes)
        playbackCDNProbeRefreshIntervalMinutes = normalizedMinutes
        userDefaults.set(normalizedMinutes, forKey: Self.playbackCDNProbeRefreshIntervalMinutesKey)
    }

    func setPlaybackNetworkAddressFamilyPreference(_ preference: PlaybackNetworkAddressFamilyPreference) {
        playbackNetworkAddressFamilyPreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.playbackNetworkAddressFamilyPreferenceKey)
        clearTemporaryPlaybackCDNAvoidance()
        clearPlaybackCDNProbeSnapshots()
    }

    func setPrefersBackupAudioURL(_ isEnabled: Bool) {
        prefersBackupAudioURL = isEnabled
        userDefaults.set(isEnabled, forKey: Self.prefersBackupAudioURLKey)
    }

    func effectivePreferredVideoQuality(for networkClass: PlaybackEnvironment.NetworkClass) -> Int? {
        Self.effectivePreferredVideoQuality(
            preferred: preferredVideoQuality,
            cellular: cellularPreferredVideoQuality,
            networkClass: networkClass
        )
    }

    nonisolated static func effectivePreferredVideoQuality(
        preferred: Int?,
        cellular: Int?,
        networkClass: PlaybackEnvironment.NetworkClass
    ) -> Int? {
        switch networkClass {
        case .cellular, .constrained:
            return cellular ?? preferred
        case .wifi, .unknown:
            return preferred
        }
    }

    func effectivePlaybackCDNPreference(for preference: PlaybackCDNPreference) -> PlaybackCDNPreference {
        guard preference == .automatic else { return preference }
        return playbackCDNRecommendation(allowExpired: true) ?? .automatic
    }

    @discardableResult
    func temporarilyAvoidAutomaticPlaybackCDN(
        _ preference: PlaybackCDNPreference,
        duration: TimeInterval = 10 * 60
    ) -> Bool {
        guard playbackCDNPreference == .automatic,
            preference.isManualHost
        else { return false }
        let expiration = Date().addingTimeInterval(max(30, duration))
        temporarilyAvoidedPlaybackCDNPreferences[preference] = expiration
        objectWillChange.send()
        return true
    }

    func setPlaybackCDNProbeSnapshot(_ snapshot: PlaybackCDNProbeSnapshot?) {
        let contextKey = currentPlaybackCDNProbeContextKey
        let previousSnapshot = playbackCDNProbeSnapshotsByContext[contextKey]
        let currentPreference =
            previousSnapshot?.recommendedPreference
            ?? previousSnapshot?.actionableResults.first?.preference
        let keepsCurrentRecommendation =
            playbackCDNPreference == .automatic
            && currentPreference.map { !isPlaybackCDNTemporarilyAvoided($0) } != false
        let snapshot =
            playbackCDNPreference == .automatic
            ? snapshot?.stabilizedRecommendation(
                previous: previousSnapshot,
                keepsCurrentRecommendation: keepsCurrentRecommendation
            )
            : snapshot
        playbackCDNProbeSnapshot = snapshot
        if let snapshot {
            playbackCDNProbeSnapshotsByContext[contextKey] = snapshot
            if let data = try? JSONEncoder().encode(snapshot) {
                userDefaults.set(data, forKey: Self.playbackCDNProbeSnapshotKey)
            }
        } else {
            playbackCDNProbeSnapshotsByContext[contextKey] = nil
            userDefaults.removeObject(forKey: Self.playbackCDNProbeSnapshotKey)
        }
        persistPlaybackCDNProbeSnapshotsByContext()
    }

    func syncPlaybackCDNProbeSnapshotForCurrentContext() {
        let currentSnapshot = playbackCDNProbeSnapshotsByContext[currentPlaybackCDNProbeContextKey]
        guard playbackCDNProbeSnapshot != currentSnapshot else { return }
        playbackCDNProbeSnapshot = currentSnapshot
    }

    private func playbackCDNRecommendation(allowExpired: Bool) -> PlaybackCDNPreference? {
        guard let snapshot = playbackCDNProbeSnapshotForCurrentContext,
            allowExpired || !snapshot.isExpired(freshnessInterval: playbackCDNProbeRefreshInterval)
        else { return nil }
        var seenPreferences = Set<PlaybackCDNPreference>()
        var candidates = [PlaybackCDNPreference]()
        func appendCandidate(_ preference: PlaybackCDNPreference?) {
            guard let preference,
                snapshot.result(for: preference)?.isActionableForPlaybackRecommendation == true,
                seenPreferences.insert(preference).inserted
            else { return }
            candidates.append(preference)
        }
        appendCandidate(snapshot.recommendedPreference)
        for result in snapshot.actionableResults {
            appendCandidate(result.preference)
        }
        return candidates.first { !isPlaybackCDNTemporarilyAvoided($0) }
    }

    private func isPlaybackCDNTemporarilyAvoided(_ preference: PlaybackCDNPreference, now: Date = Date()) -> Bool {
        guard let expiresAt = temporarilyAvoidedPlaybackCDNPreferences[preference] else { return false }
        return expiresAt > now
    }

    private func clearTemporaryPlaybackCDNAvoidance() {
        guard !temporarilyAvoidedPlaybackCDNPreferences.isEmpty else { return }
        temporarilyAvoidedPlaybackCDNPreferences.removeAll()
        objectWillChange.send()
    }

    private var currentPlaybackCDNProbeContextKey: String {
        Self.playbackCDNProbeContextKey(
            networkClass: PlaybackEnvironment.current.networkClass,
            addressFamilyPreference: playbackNetworkAddressFamilyPreference
        )
    }

    private func clearPlaybackCDNProbeSnapshots() {
        playbackCDNProbeSnapshot = nil
        playbackCDNProbeSnapshotsByContext.removeAll()
        userDefaults.removeObject(forKey: Self.playbackCDNProbeSnapshotKey)
        userDefaults.removeObject(forKey: Self.playbackCDNProbeSnapshotsByContextKey)
    }

    private func persistPlaybackCDNProbeSnapshotsByContext() {
        guard !playbackCDNProbeSnapshotsByContext.isEmpty,
            let data = try? JSONEncoder().encode(playbackCDNProbeSnapshotsByContext)
        else {
            userDefaults.removeObject(forKey: Self.playbackCDNProbeSnapshotsByContextKey)
            return
        }
        userDefaults.set(data, forKey: Self.playbackCDNProbeSnapshotsByContextKey)
    }

    private func persistPlaybackProgress() {
        if playbackProgressByBVID.count > Self.maxStoredPlaybackProgressCount {
            playbackProgressByBVID = Dictionary(
                uniqueKeysWithValues: playbackProgressByBVID
                    .values
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(Self.maxStoredPlaybackProgressCount)
                    .map { ($0.bvid, $0) }
            )
        }
        guard !playbackProgressByBVID.isEmpty,
            let data = try? JSONEncoder().encode(playbackProgressByBVID)
        else {
            userDefaults.removeObject(forKey: Self.playbackProgressByBVIDKey)
            return
        }
        userDefaults.set(data, forKey: Self.playbackProgressByBVIDKey)
        userDefaults.synchronize()
    }

    private static func playbackCDNProbeContextKey(
        networkClass: PlaybackEnvironment.NetworkClass,
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference
    ) -> String {
        "\(networkClass.cacheKey)|\(addressFamilyPreference.rawValue)"
    }

    func setBlocksAdDynamics(_ isEnabled: Bool) {
        blocksAdDynamics = isEnabled
        userDefaults.set(isEnabled, forKey: Self.blocksAdDynamicsKey)
    }

    func setBlocksGoodsDynamics(_ isEnabled: Bool) {
        blocksGoodsDynamics = isEnabled
        userDefaults.set(isEnabled, forKey: Self.blocksGoodsDynamicsKey)
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        blocksGoodsComments = isEnabled
        userDefaults.set(isEnabled, forKey: Self.blocksGoodsCommentsKey)
    }

    func setBlockedDynamicKeywords(_ keywords: [String]) {
        blockedDynamicKeywords = Self.normalizedBlockedDynamicKeywords(keywords)
        persistBlockedDynamicKeywords()
    }

    func addBlockedDynamicKeyword(_ keyword: String) {
        let normalizedKeyword = Self.normalizedBlockedDynamicKeyword(keyword)
        guard !normalizedKeyword.isEmpty else { return }
        guard
            !blockedDynamicKeywords.contains(where: {
                Self.blockedDynamicKeywordKey($0) == Self.blockedDynamicKeywordKey(normalizedKeyword)
            })
        else {
            return
        }
        blockedDynamicKeywords.append(normalizedKeyword)
        persistBlockedDynamicKeywords()
    }

    func removeBlockedDynamicKeyword(_ keyword: String) {
        let keywordKey = Self.blockedDynamicKeywordKey(keyword)
        let updated = blockedDynamicKeywords.filter { Self.blockedDynamicKeywordKey($0) != keywordKey }
        guard updated.count != blockedDynamicKeywords.count else { return }
        blockedDynamicKeywords = updated
        persistBlockedDynamicKeywords()
    }

    func removeBlockedDynamicKeywords(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        blockedDynamicKeywords.remove(atOffsets: offsets)
        persistBlockedDynamicKeywords()
    }

    func clearBlockedDynamicKeywords() {
        guard !blockedDynamicKeywords.isEmpty else { return }
        blockedDynamicKeywords = []
        persistBlockedDynamicKeywords()
    }

    func setRecommendMinimumDurationSeconds(_ seconds: Int) {
        recommendMinimumDurationSeconds = Self.normalizedRecommendFilterValue(
            seconds,
            supportedValues: Self.supportedRecommendMinimumDurations
        )
        userDefaults.set(recommendMinimumDurationSeconds, forKey: Self.recommendMinimumDurationSecondsKey)
    }

    func setRecommendMinimumViewCount(_ count: Int) {
        recommendMinimumViewCount = Self.normalizedRecommendFilterValue(
            count,
            supportedValues: Self.supportedRecommendMinimumViews
        )
        userDefaults.set(recommendMinimumViewCount, forKey: Self.recommendMinimumViewCountKey)
    }

    func setRecommendMinimumLikeRatioPercent(_ percent: Int) {
        recommendMinimumLikeRatioPercent = Self.normalizedRecommendFilterValue(
            percent,
            supportedValues: Self.supportedRecommendMinimumLikeRatios
        )
        userDefaults.set(recommendMinimumLikeRatioPercent, forKey: Self.recommendMinimumLikeRatioPercentKey)
    }

    func setAppliesRecommendFiltersToRelatedVideos(_ isEnabled: Bool) {
        appliesRecommendFiltersToRelatedVideos = isEnabled
        userDefaults.set(isEnabled, forKey: Self.appliesRecommendFiltersToRelatedVideosKey)
    }

    func setBlockedRecommendKeywords(_ keywords: [String]) {
        blockedRecommendKeywords = Self.normalizedBlockedRecommendKeywords(keywords)
        persistBlockedRecommendKeywords()
    }

    func addBlockedRecommendKeyword(_ keyword: String) {
        let normalizedKeyword = Self.normalizedBlockedRecommendKeyword(keyword)
        guard !normalizedKeyword.isEmpty else { return }
        guard
            !blockedRecommendKeywords.contains(where: {
                Self.blockedRecommendKeywordKey($0) == Self.blockedRecommendKeywordKey(normalizedKeyword)
            })
        else {
            return
        }
        blockedRecommendKeywords.append(normalizedKeyword)
        persistBlockedRecommendKeywords()
    }

    func removeBlockedRecommendKeyword(_ keyword: String) {
        let keywordKey = Self.blockedRecommendKeywordKey(keyword)
        let updated = blockedRecommendKeywords.filter { Self.blockedRecommendKeywordKey($0) != keywordKey }
        guard updated.count != blockedRecommendKeywords.count else { return }
        blockedRecommendKeywords = updated
        persistBlockedRecommendKeywords()
    }

    func removeBlockedRecommendKeywords(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        blockedRecommendKeywords.remove(atOffsets: offsets)
        persistBlockedRecommendKeywords()
    }

    func clearBlockedRecommendKeywords() {
        guard !blockedRecommendKeywords.isEmpty else { return }
        blockedRecommendKeywords = []
        persistBlockedRecommendKeywords()
    }

    func setDanmakuEnabled(_ isEnabled: Bool) {
        danmakuEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.danmakuEnabledKey)
    }

    func setDanmakuSettings(_ settings: DanmakuSettings) {
        let normalizedSettings = settings.normalized
        danmakuSettings = normalizedSettings
        guard let data = try? JSONEncoder().encode(normalizedSettings) else { return }
        userDefaults.set(data, forKey: Self.danmakuSettingsKey)
    }

    func setSponsorBlockEnabled(_ isEnabled: Bool) {
        sponsorBlockEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.sponsorBlockEnabledKey)
    }

    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        pictureInPictureEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.pictureInPictureEnabledKey)
    }

    func setPlayerPerformanceOverlayEnabled(_ isEnabled: Bool) {
        playerPerformanceOverlayEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.playerPerformanceOverlayEnabledKey)
    }

    func setResourceLoadingResumePacketWarmupEnabled(_ isEnabled: Bool) {
        resourceLoadingResumePacketWarmupEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.resourceLoadingResumePacketWarmupEnabledKey)
    }

    func setPlaybackPlayableFallbackDeadlineExperimentEnabled(_ isEnabled: Bool) {
        playbackPlayableFallbackDeadlineExperimentEnabled = isEnabled
        userDefaults.set(
            isEnabled,
            forKey: Self.playbackPlayableFallbackDeadlineExperimentEnabledKey
        )
    }

    func setVideoRotationFrameReportOverlayEnabled(_ isEnabled: Bool) {
        videoRotationFrameReportOverlayEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.videoRotationFrameReportOverlayEnabledKey)
    }

    func setVideoDetailNavigationLatencyDiagnosticsEnabled(_ isEnabled: Bool) {
        videoDetailNavigationLatencyDiagnosticsEnabled = isEnabled
        userDefaults.set(
            isEnabled,
            forKey: Self.videoDetailNavigationLatencyDiagnosticsEnabledKey
        )
    }

    func setPlayerControlEdgeScrimEnabled(_ isEnabled: Bool) {
        playerControlEdgeScrimEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.playerControlEdgeScrimEnabledKey)
    }

    func setShowsVideoDetailNetworkDiagnosticsButton(_ isEnabled: Bool) {
        showsVideoDetailNetworkDiagnosticsButton = isEnabled
        userDefaults.set(isEnabled, forKey: Self.showsVideoDetailNetworkDiagnosticsButtonKey)
    }

    func setShowsVideoDetailPinnedProgressBar(_ isEnabled: Bool) {
        showsVideoDetailPinnedProgressBar = isEnabled
        userDefaults.set(isEnabled, forKey: Self.showsVideoDetailPinnedProgressBarKey)
    }

    func setVideoDetailAutoplayEnabled(_ isEnabled: Bool) {
        videoDetailAutoplayEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.videoDetailAutoplayEnabledKey)
    }

    func setVideoListenPlaybackOrder(_ order: VideoListenPlaybackOrder) {
        videoListenPlaybackOrder = order
        userDefaults.set(order.rawValue, forKey: Self.videoListenPlaybackOrderKey)
    }

    func setVideoListenPlaylistSortOrder(_ order: VideoListenPlaylistSortOrder) {
        videoListenPlaylistSortOrder = order
        userDefaults.set(order.rawValue, forKey: Self.videoListenPlaylistSortOrderKey)
    }

    func setCellularBiliTrafficCompatibilityExperimentEnabled(_ isEnabled: Bool) {
        cellularBiliTrafficCompatibilityExperimentEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.cellularBiliTrafficCompatibilityExperimentEnabledKey)
        Task {
            await LocalHLSBridge.clearWarmupCache()
        }
    }

    func setIncognitoModeEnabled(_ isEnabled: Bool) {
        incognitoModeEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.incognitoModeEnabledKey)
    }

    func setGuestModeEnabled(_ isEnabled: Bool) {
        guestModeEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.guestModeEnabledKey)
    }

    func setMultiAccountExperimentEnabled(_ isEnabled: Bool) {
        multiAccountExperimentEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.multiAccountExperimentEnabledKey)
    }

    func setDynamicCommentHitAreaVisualizationExperimentEnabled(_ isEnabled: Bool) {
        dynamicCommentHitAreaVisualizationExperimentEnabled = isEnabled
        userDefaults.set(
            isEnabled,
            forKey: Self.dynamicCommentHitAreaVisualizationExperimentEnabledKey
        )
    }

    private static func boolValue(forKey key: String, in userDefaults: UserDefaults) -> Bool? {
        if let value = userDefaults.object(forKey: key) as? Bool {
            return value
        }
        guard let value = userDefaults.object(forKey: key) as? String else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y":
            return true
        case "0", "false", "no", "n":
            return false
        default:
            return nil
        }
    }

    func setNativePullRefreshEnabled(_ isEnabled: Bool) {
        nativePullRefreshEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.nativePullRefreshEnabledKey)
    }

    func setMinimizesTabBarOnScroll(_ isEnabled: Bool) {
        minimizesTabBarOnScroll = isEnabled
        userDefaults.set(isEnabled, forKey: Self.minimizesTabBarOnScrollKey)
    }

    func setVideoDetailSegmentedPickerGlassStyle(
        _ glassStyle: VideoDetailSegmentedPickerGlassStyle
    ) {
        videoDetailSegmentedPickerGlassStyle = glassStyle
        userDefaults.set(glassStyle.rawValue, forKey: Self.videoDetailSegmentedPickerGlassStyleKey)
    }

    func setLiquidGlassStylePreference(_ preference: AppLiquidGlassStylePreference) {
        liquidGlassStylePreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.liquidGlassStylePreferenceKey)
    }

    func setRemoteImageQualityPreference(_ preference: RemoteImageQualityPreference) {
        remoteImageQualityPreference = preference
        userDefaults.set(preference.rawValue, forKey: Self.remoteImageQualityPreferenceKey)
    }

    func setVideoCoverBadgeShadowOpacity(_ opacity: Double) {
        let normalizedOpacity = VideoCoverBadgeShadow.normalized(opacity)
        videoCoverBadgeShadowOpacity = normalizedOpacity
        userDefaults.set(normalizedOpacity, forKey: Self.videoCoverBadgeShadowOpacityKey)
    }

    func setVideoCoverBottomScrimEnabled(_ isEnabled: Bool) {
        videoCoverBottomScrimEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.videoCoverBottomScrimEnabledKey)
    }

    func setShowsVideoCoverDurationBadges(_ isEnabled: Bool) {
        showsVideoCoverDurationBadges = isEnabled
        userDefaults.set(isEnabled, forKey: Self.videoCoverDurationBadgesEnabledKey)
    }

    func setRemoteImageDiagnosticsEnabled(_ isEnabled: Bool) {
        remoteImageDiagnosticsEnabled = isEnabled
        RemoteImageDiagnosticsSettings.setEnabled(isEnabled, in: userDefaults)
        RemoteImageDisplayMemoryCache.shared.resetDiagnostics()
        RemoteImageCDNHealthMemory.shared.resetDiagnostics()
        Task { @MainActor [weak self] in
            guard let self, self.remoteImageDiagnosticsEnabled == isEnabled else { return }
            await RemoteImageCache.shared.resetDiagnostics()
            await RemoteImageLoadSuppressionGate.shared.resetDiagnostics()
        }
    }

    func setForce120HzScrollingEnabled(_ isEnabled: Bool) {
        force120HzScrollingEnabled = isEnabled
        RefreshRateManager.shared.setForce120HzEnabled(isEnabled)
    }

    func setRootTab(_ tab: AppTab, isVisible: Bool) {
        guard tab.canHideFromRootTabBar else { return }
        var tabs = visibleRootTabs
        if isVisible {
            if !tabs.contains(tab) {
                let defaultIndex = AppTab.defaultVisibleTabs.firstIndex(of: tab) ?? tabs.count
                let insertionIndex =
                    tabs.firstIndex { existing in
                        let existingIndex = AppTab.defaultVisibleTabs.firstIndex(of: existing) ?? Int.max
                        return existingIndex > defaultIndex
                    } ?? tabs.count
                tabs.insert(tab, at: insertionIndex)
            }
        } else {
            tabs.removeAll { $0 == tab }
        }
        setVisibleRootTabs(tabs)
    }

    func resetVisibleRootTabs() {
        setVisibleRootTabs(AppTab.defaultVisibleTabs)
    }

    private func setVisibleRootTabs(_ tabs: [AppTab]) {
        let normalized = AppTab.normalizedVisibleTabs(tabs)
        guard normalized != visibleRootTabs else { return }
        visibleRootTabs = normalized
        userDefaults.set(normalized.map(\.rawValue), forKey: Self.visibleRootTabsKey)
    }

    func setHomeRefreshTriggerDistance(_ distance: Double) {
        let normalizedDistance = Self.normalizedHomeRefreshDistance(distance)
        homeRefreshTriggerDistance = normalizedDistance
        userDefaults.set(normalizedDistance, forKey: Self.homeRefreshTriggerDistanceKey)
    }

    var usesNativePullRefresh: Bool {
        nativePullRefreshEnabled
    }

    var usesCustomPullRefresh: Bool {
        !usesNativePullRefresh
    }

    func setHomeFeedLayout(_ layout: HomeFeedLayout) {
        homeFeedLayout = layout
        userDefaults.set(layout.rawValue, forKey: Self.homeFeedLayoutKey)
    }

    func setShowsHotSearches(_ isEnabled: Bool) {
        showsHotSearches = isEnabled
        userDefaults.set(isEnabled, forKey: Self.showsHotSearchesKey)
    }

    private static func normalizedPlaybackRate(_ rate: Double) -> Double {
        supportedPlaybackRates.contains(rate) ? rate : 1.0
    }

    private static func normalizedPlaybackHistorySyncThresholdSeconds(_ seconds: Int) -> Int {
        supportedPlaybackHistorySyncThresholdSeconds.contains(seconds)
            ? seconds
            : defaultPlaybackHistorySyncThresholdSeconds
    }

    private static func normalizedVideoQuality(_ quality: Int?) -> Int? {
        guard let quality, supportedVideoQualities.contains(quality) else { return nil }
        return quality
    }

    private static func normalizedPlaybackCDNProbeRefreshIntervalMinutes(_ minutes: Int) -> Int {
        min(
            max(minutes, playbackCDNProbeRefreshIntervalRange.lowerBound),
            playbackCDNProbeRefreshIntervalRange.upperBound)
    }

    private static func normalizedVisibleRootTabs(_ rawValues: [String]?) -> [AppTab] {
        guard let rawValues, !rawValues.isEmpty else {
            return AppTab.defaultVisibleTabs
        }
        let tabs = rawValues.compactMap(AppTab.init(rawValue:))
        return AppTab.normalizedVisibleTabs(tabs)
    }

    static func videoQualityTitle(_ quality: Int?) -> String {
        BiliVideoQuality.title(for: quality)
    }

    private static func normalizedHomeRefreshDistance(_ distance: Double) -> Double {
        min(max(distance, homeRefreshDistanceRange.lowerBound), homeRefreshDistanceRange.upperBound)
    }

    private func persistBlockedDynamicKeywords() {
        guard !blockedDynamicKeywords.isEmpty else {
            userDefaults.removeObject(forKey: Self.blockedDynamicKeywordsKey)
            return
        }
        userDefaults.set(blockedDynamicKeywords, forKey: Self.blockedDynamicKeywordsKey)
    }

    private func persistBlockedRecommendKeywords() {
        guard !blockedRecommendKeywords.isEmpty else {
            userDefaults.removeObject(forKey: Self.blockedRecommendKeywordsKey)
            return
        }
        userDefaults.set(blockedRecommendKeywords, forKey: Self.blockedRecommendKeywordsKey)
    }

    private static func normalizedBlockedDynamicKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.compactMap { keyword in
            let normalized = normalizedBlockedDynamicKeyword(keyword)
            guard !normalized.isEmpty else { return nil }
            let key = blockedDynamicKeywordKey(normalized)
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private static func normalizedBlockedDynamicKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func blockedDynamicKeywordKey(_ keyword: String) -> String {
        normalizedBlockedDynamicKeyword(keyword).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    private static func normalizedBlockedRecommendKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.compactMap { keyword in
            let normalized = normalizedBlockedRecommendKeyword(keyword)
            guard !normalized.isEmpty else { return nil }
            let key = blockedRecommendKeywordKey(normalized)
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private static func normalizedBlockedRecommendKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func blockedRecommendKeywordKey(_ keyword: String) -> String {
        normalizedBlockedRecommendKeyword(keyword).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    private static func normalizedRecommendFilterValue(_ value: Int?, supportedValues: [Int]) -> Int {
        guard let value, supportedValues.contains(value) else {
            return supportedValues.first ?? 0
        }
        return value
    }
}

extension PlaybackEnvironment.NetworkClass {
    fileprivate var cacheKey: String {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .constrained:
            return "constrained"
        case .unknown:
            return "unknown"
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum VideoDetailSegmentedPickerGlassStyle: String, CaseIterable, Identifiable {
    case clear
    case regular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear:
            return "Clear"
        case .regular:
            return "Regular"
        }
    }
}

enum HomeFeedLayout: String, CaseIterable, Identifiable {
    case doubleColumn
    case borderedDoubleColumn
    case borderedSingleColumn
    case singleColumn

    var id: String { rawValue }

    var isDoubleColumn: Bool {
        switch self {
        case .doubleColumn, .borderedDoubleColumn:
            return true
        case .borderedSingleColumn, .singleColumn:
            return false
        }
    }

    var title: String {
        switch self {
        case .doubleColumn:
            return "双列"
        case .borderedDoubleColumn:
            return "有边框双列"
        case .borderedSingleColumn:
            return "有边框单列"
        case .singleColumn:
            return "单列"
        }
    }

    var systemImage: String {
        switch self {
        case .doubleColumn:
            return "square.grid.2x2"
        case .borderedDoubleColumn:
            return "square.grid.2x2.fill"
        case .borderedSingleColumn:
            return "rectangle.grid.1x2.fill"
        case .singleColumn:
            return "rectangle.grid.1x2"
        }
    }
}
