import Combine
import SwiftUI

struct LiveDanmakuOverlaySnapshot: Equatable {
    var items: [DanmakuItem]
    var itemsRevision: Int
    var playbackTime: TimeInterval
    var isEnabled: Bool
    var settings: DanmakuSettings

    init(store: LiveDanmakuRenderStore) {
        items = store.items
        itemsRevision = store.itemsRevision
        playbackTime = store.playbackTime
        isEnabled = store.isEnabled
        settings = store.settings
    }
}

/// Keeps high-frequency live-danmaku mutations out of the system rotation
/// transaction, while retaining the rendered layer and its active animations.
@MainActor
final class LiveDanmakuOverlayState: ObservableObject {
    @Published private(set) var snapshot: LiveDanmakuOverlaySnapshot

    private let store: LiveDanmakuRenderStore
    private let rotationState: LiveRotationSurfaceAlignmentState
    private var cancellables = Set<AnyCancellable>()
    private var publishTask: Task<Void, Never>?
    private var defersUpdates = false
    private var hasDeferredSnapshotUpdate = false

    init(
        store: LiveDanmakuRenderStore,
        rotationState: LiveRotationSurfaceAlignmentState
    ) {
        self.store = store
        self.rotationState = rotationState
        self.snapshot = LiveDanmakuOverlaySnapshot(store: store)

        store.$items
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$itemsRevision
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$playbackTime
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$isEnabled
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$settings
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
    }

    deinit {
        publishTask?.cancel()
    }

    func setUpdatesDeferred(_ deferred: Bool) {
        guard defersUpdates != deferred else { return }
        defersUpdates = deferred
        if !deferred {
            publishTask?.cancel()
            publishTask = nil
            publishCurrentSnapshot()
        }
    }

    private func schedulePublish() {
        // Retain only the fact that an update occurred. Building a full snapshot
        // copies the live item list and is unnecessary while it cannot render.
        if defersUpdates {
            markDeferredSnapshotUpdateIfNeeded()
            return
        }
        guard publishTask == nil else { return }
        publishTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.publishTask = nil
            self.publishCurrentSnapshot()
        }
    }

    private func publishCurrentSnapshot() {
        let nextSnapshot = LiveDanmakuOverlaySnapshot(store: store)
        guard nextSnapshot != snapshot else {
            hasDeferredSnapshotUpdate = false
            return
        }
        if defersUpdates {
            markDeferredSnapshotUpdateIfNeeded()
            return
        }

        let hadDeferredSnapshotUpdate = hasDeferredSnapshotUpdate
        hasDeferredSnapshotUpdate = false
        snapshot = nextSnapshot
        if hadDeferredSnapshotUpdate {
            rotationState.recordOverlayFlush()
        }
    }

    private func markDeferredSnapshotUpdateIfNeeded() {
        guard !hasDeferredSnapshotUpdate else { return }
        hasDeferredSnapshotUpdate = true
        rotationState.recordOverlayDeferred()
    }
}

struct LiveDanmakuOverlay: View {
    @ObservedObject var state: LiveDanmakuOverlayState
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let usesLandscapeChrome: Bool
    let isLayoutTransitioning: Bool
    let videoAspectRatio: CGFloat

    var body: some View {
        let snapshot = state.snapshot
        let shouldDriveLiveDanmaku = playerViewModel.isPlaying || playerViewModel.wantsAutoplay
        let isVisibleInCurrentOrientation = usesLandscapeChrome || !snapshot.settings.hidesInPortrait

        GeometryReader { proxy in
            DanmakuOverlayView(
                items: snapshot.items,
                itemsRevision: snapshot.itemsRevision,
                currentTime: snapshot.playbackTime,
                isPlaying: shouldDriveLiveDanmaku,
                playbackRate: 1,
                isEnabled: snapshot.isEnabled && isVisibleInCurrentOrientation,
                hasPresentedPlayback: playerViewModel.hasPresentedPlayback || shouldDriveLiveDanmaku,
                isLoadShedding: false,
                settings: snapshot.settings,
                topInset: usesLandscapeChrome ? 28 : 8,
                bottomInset: usesLandscapeChrome ? 84 : 54,
                isLayoutTransitioning: isLayoutTransitioning,
                playbackClock: nil,
                onPlaybackTime: nil
            )
            .padding(videoContentInsets(in: proxy.size))
            .padding(.horizontal, usesLandscapeChrome ? 18 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func videoContentInsets(in size: CGSize) -> EdgeInsets {
        guard size.width > 1, size.height > 1, videoAspectRatio > 0.1 else {
            return EdgeInsets()
        }

        let containerAspectRatio = size.width / size.height
        if videoAspectRatio > containerAspectRatio {
            let fittedHeight = size.width / videoAspectRatio
            let verticalInset = max(0, (size.height - fittedHeight) / 2)
            return EdgeInsets(top: verticalInset, leading: 0, bottom: verticalInset, trailing: 0)
        }

        let fittedWidth = size.height * videoAspectRatio
        let horizontalInset = max(0, (size.width - fittedWidth) / 2)
        return EdgeInsets(top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
    }
}

struct LiveDanmakuSettingsSheet: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DanmakuSettingsHeaderSectionContent(
                        isDanmakuEnabled: viewModel.isDanmakuEnabled,
                        settings: viewModel.danmakuSettings,
                        summary: settingsSummary,
                        toggleDanmaku: viewModel.toggleDanmaku
                    )
                }

                DanmakuSettingsDisplayAreaSection(displayArea: displayAreaBinding)
                DanmakuSettingsPortraitVisibilitySection(
                    hidesDanmakuInPortrait: hidesInPortraitBinding
                )
                DanmakuSettingsTextSection(
                    settings: viewModel.danmakuSettings,
                    fontScale: fontScaleBinding,
                    fontWeight: fontWeightBinding
                )
                DanmakuSettingsOpacitySection(
                    settings: viewModel.danmakuSettings,
                    opacity: opacityBinding
                )
            }
            .navigationTitle("弹幕设置")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                VideoDetailDoneToolbar(finish: { dismiss() })
            }
        }
    }

    private var settingsSummary: String {
        if viewModel.isDanmakuEnabled {
            return "当前使用 \(viewModel.danmakuSettings.displayArea.title)，字号 \(Int((viewModel.danmakuSettings.fontScale * 100).rounded()))%，不透明度 \(Int((viewModel.danmakuSettings.opacity * 100).rounded()))%。"
        }
        return "弹幕已关闭，直播画面不会显示滚动评论。"
    }

    private var displayAreaBinding: Binding<DanmakuDisplayArea> {
        Binding(
            get: { viewModel.danmakuSettings.displayArea },
            set: { updateSettings(displayArea: $0) }
        )
    }

    private var hidesInPortraitBinding: Binding<Bool> {
        Binding(
            get: { viewModel.danmakuSettings.hidesInPortrait },
            set: { updateSettings(hidesInPortrait: $0) }
        )
    }

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { viewModel.danmakuSettings.fontScale },
            set: { updateSettings(fontScale: $0) }
        )
    }

    private var fontWeightBinding: Binding<DanmakuFontWeightOption> {
        Binding(
            get: { viewModel.danmakuSettings.fontWeight },
            set: { updateSettings(fontWeight: $0) }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { viewModel.danmakuSettings.opacity },
            set: { updateSettings(opacity: $0) }
        )
    }

    private func updateSettings(
        fontScale: Double? = nil,
        opacity: Double? = nil,
        displayArea: DanmakuDisplayArea? = nil,
        fontWeight: DanmakuFontWeightOption? = nil,
        hidesInPortrait: Bool? = nil
    ) {
        var settings = viewModel.danmakuSettings
        if let fontScale {
            settings.fontScale = fontScale
        }
        if let opacity {
            settings.opacity = opacity
        }
        if let displayArea {
            settings.displayArea = displayArea
        }
        if let fontWeight {
            settings.fontWeight = fontWeight
        }
        if let hidesInPortrait {
            settings.hidesInPortrait = hidesInPortrait
        }
        viewModel.updateDanmakuSettings(settings)
    }
}
