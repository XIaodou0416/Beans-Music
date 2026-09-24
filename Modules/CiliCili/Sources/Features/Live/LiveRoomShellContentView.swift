import Combine
import SwiftUI

private enum LiveRoomChatLayoutMetrics {
    static let chatOverlaySpacing: CGFloat = 12
    static let bottomContentClearance: CGFloat = 24
}

private enum LiveRoomTheme {
    static let background = Color(.systemGroupedBackground)
    static let chatBubble = Color(.systemGray5)
    static let chatSender = Color(.secondaryLabel)
    static let highlightedChatBubble = Color.orange.opacity(0.16)
    static let highlightedChatSender = Color.orange
}

struct LiveRoomChatTimelineSnapshot: Equatable {
    var items: [DanmakuItem]
    var itemsRevision: Int
    var isEnabled: Bool
    var connectionPhase: LiveDanmakuDiagnosticPhase
    var connectionError: String?
    var isLoadingHistory: Bool
    var historyError: String?

    init(store: LiveDanmakuRenderStore) {
        items = store.chatItems
        itemsRevision = store.chatItemsRevision
        isEnabled = store.isEnabled
        connectionPhase = store.connectionPhase
        connectionError = store.connectionError
        isLoadingHistory = store.isLoadingHistory
        historyError = store.historyError
    }
}

/// Chat can receive several messages per second. During the experimental
/// rotation path, retain the rendered list and publish its newest snapshot once
/// the player surface has settled.
@MainActor
final class LiveRoomChatTimelineState: ObservableObject {
    @Published private(set) var snapshot: LiveRoomChatTimelineSnapshot

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
        self.snapshot = LiveRoomChatTimelineSnapshot(store: store)

        store.$chatItems
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$chatItemsRevision
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$isEnabled
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$connectionPhase
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$connectionError
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$isLoadingHistory
            .sink { [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        store.$historyError
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
        // The rendered list is hidden during rotation. Recording one dirty bit
        // avoids repeatedly copying up to 120 rows on the main actor.
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
        let nextSnapshot = LiveRoomChatTimelineSnapshot(store: store)
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
            rotationState.recordChatFlush()
        }
    }

    private func markDeferredSnapshotUpdateIfNeeded() {
        guard !hasDeferredSnapshotUpdate else { return }
        hasDeferredSnapshotUpdate = true
        rotationState.recordChatDeferred()
    }
}

/// 直播详情的非播放器底层，承载背景、主播栏和聊天时间线。
struct LiveRoomShellContentView: View {
    @MainActor
    final class State: ObservableObject {
        struct Layout: Equatable {
            var width: CGFloat
            var height: CGFloat
            var topSafeAreaInset: CGFloat
            var bottomSafeAreaInset: CGFloat
            var playerHeight: CGFloat
        }

        @Published private(set) var layout: Layout
        let chatTimelineState: LiveRoomChatTimelineState

        var layoutWidth: CGFloat { layout.width }
        var layoutHeight: CGFloat { layout.height }
        var topSafeAreaInset: CGFloat { layout.topSafeAreaInset }
        var bottomSafeAreaInset: CGFloat { layout.bottomSafeAreaInset }
        var playerHeight: CGFloat { layout.playerHeight }

        init(
            layoutWidth: CGFloat = 393,
            layoutHeight: CGFloat = 852,
            chatStore: LiveDanmakuRenderStore,
            rotationState: LiveRotationSurfaceAlignmentState
        ) {
            self.layout = Layout(
                width: layoutWidth,
                height: layoutHeight,
                topSafeAreaInset: 0,
                bottomSafeAreaInset: 0,
                playerHeight: 0
            )
            self.chatTimelineState = LiveRoomChatTimelineState(
                store: chatStore,
                rotationState: rotationState
            )
        }

        func setChatUpdatesDeferred(_ deferred: Bool) {
            chatTimelineState.setUpdatesDeferred(deferred)
        }

        func update(
            layoutWidth: CGFloat,
            layoutHeight: CGFloat,
            topSafeAreaInset: CGFloat,
            bottomSafeAreaInset: CGFloat,
            playerHeight: CGFloat
        ) {
            let nextLayout = Layout(
                width: resolvedLayoutValue(current: layout.width, candidate: layoutWidth),
                height: resolvedLayoutValue(current: layout.height, candidate: layoutHeight),
                topSafeAreaInset: resolvedLayoutValue(
                    current: layout.topSafeAreaInset,
                    candidate: topSafeAreaInset
                ),
                bottomSafeAreaInset: resolvedLayoutValue(
                    current: layout.bottomSafeAreaInset,
                    candidate: bottomSafeAreaInset
                ),
                playerHeight: resolvedLayoutValue(
                    current: layout.playerHeight,
                    candidate: playerHeight
                )
            )
            guard nextLayout != layout else { return }
            layout = nextLayout
        }

        private func resolvedLayoutValue(current: CGFloat, candidate: CGFloat) -> CGFloat {
            abs(current - candidate) > 0.5 ? candidate : current
        }
    }

    @ObservedObject var viewModel: LiveRoomViewModel
    @ObservedObject var state: State
    let onNavigateBack: () -> Void

    init(
        viewModel: LiveRoomViewModel,
        state: State,
        onNavigateBack: @escaping () -> Void
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _state = ObservedObject(wrappedValue: state)
        self.onNavigateBack = onNavigateBack
    }

    var body: some View {
        LiveRoomSimpleLiveLayoutView(
            viewModel: viewModel,
            state: state,
            onNavigateBack: onNavigateBack
        )
        .frame(width: state.layoutWidth, height: state.layoutHeight, alignment: .top)
        .clipped()
        .ignoresSafeArea()
    }
}

/// A stable system background remains visible while the chat tree is frozen
/// during rotation, without exposing the live cover or a fixed fallback color.
struct LiveRoomVisualBackdrop: View {
    var body: some View {
        LiveRoomTheme.background
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct LiveRoomPlainDanmakuTimeline: View {
    @ObservedObject var renderState: LiveRoomChatTimelineState
    let isDanmakuEnabled: Bool
    let bottomSafeAreaInset: CGFloat
    var additionalBottomInset: CGFloat = 0
    var usesDarkForeground = true
    let onEnableDanmaku: () -> Void
    @State private var followsLatest = true
    private let bottomAnchorID = "live-room-plain-danmaku-bottom"

    private var visibleItems: ArraySlice<DanmakuItem> {
        renderState.snapshot.items.suffix(120)
    }

    private var latestAnchorID: String {
        "\(bottomAnchorID)-\(renderState.snapshot.itemsRevision)"
    }

    private var bottomContentInset: CGFloat {
        max(bottomSafeAreaInset, 0)
            + max(additionalBottomInset, 0)
            + LiveRoomChatLayoutMetrics.bottomContentClearance
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if !isDanmakuEnabled || !renderState.snapshot.isEnabled {
                Button(action: onEnableDanmaku) {
                    Label("开启弹幕", systemImage: "text.bubble")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(usesDarkForeground ? Color.white : Color.primary)
                .biliRegularGlassEffect(interactive: true, in: Capsule())
                .padding(.trailing, 12)
                .padding(.bottom, bottomContentInset + LiveRoomChatLayoutMetrics.chatOverlaySpacing)
                .accessibilityLabel("开启直播弹幕")
            } else {
                timeline
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleItems) { item in
                        LiveRoomPlainDanmakuRow(
                            item: item,
                            usesDarkForeground: usesDarkForeground
                        )
                            .id(item.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(latestAnchorID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .padding(.bottom, bottomContentInset)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in followsLatest = false }
            )
            .onAppear {
                scrollToLatest(using: proxy, anchorID: latestAnchorID)
            }
            .onChange(of: renderState.snapshot.itemsRevision) { _, _ in
                guard followsLatest else { return }
                scrollToLatest(using: proxy, anchorID: latestAnchorID)
            }
            .overlay(alignment: .bottomTrailing) {
                if !followsLatest {
                    Button {
                        followsLatest = true
                        scrollToLatest(using: proxy, anchorID: latestAnchorID)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(usesDarkForeground ? Color.white : Color.primary)
                    .biliRegularGlassEffect(interactive: true, in: Circle())
                    .padding(.trailing, 12)
                    .padding(.bottom, bottomContentInset + LiveRoomChatLayoutMetrics.chatOverlaySpacing)
                    .accessibilityLabel("回到最新弹幕")
                }
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, anchorID: String) {
        DispatchQueue.main.async {
            proxy.scrollTo(anchorID, anchor: .bottom)
        }
    }
}

private struct LiveRoomPlainDanmakuRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: DanmakuItem
    let usesDarkForeground: Bool

    private var sender: (name: String, usesFallback: Bool) {
        guard let senderName = item.senderName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        else {
            return ("匿名用户", true)
        }
        return (senderName, false)
    }

    var body: some View {
        messageContent
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var messageContent: some View {
        if item.inlineEmotes.isEmpty {
            Text(
                "\(Text("\(sender.name)：").font(senderFont).foregroundColor(senderColor))\(Text(item.text).font(messageFont).foregroundColor(messageColor))"
            )
                .fixedSize(horizontal: false, vertical: true)
        } else {
            BiliEmoteText(
                content: nil,
                plainText: item.text,
                inlineEmotes: item.inlineEmotes,
                font: .system(size: 15),
                textColor: messageColor,
                emoteSize: 24,
                leadingName: sender.name,
                leadingNameColor: senderColor,
                showsLinkButtons: false,
                fillsAvailableWidth: true,
                typographyRole: .liveChatBody,
                leadingNameTypographyRole: .liveChatName
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var senderColor: Color {
        sender.usesFallback
            ? (usesDarkForeground ? Color.white.opacity(0.62) : Color.secondary)
            : Color.teal
    }

    private var messageColor: Color {
        usesDarkForeground ? .white : .primary
    }

    private var senderFont: Font {
        Font(
            AppTypography.Role.liveChatName.uiFont(
                contentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
        )
    }

    private var messageFont: Font {
        Font(
            AppTypography.Role.liveChatBody.uiFont(
                contentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
        )
    }

    private var accessibilityLabel: String {
        "直播弹幕，\(sender.name)：\(item.text)"
    }
}

private enum LiveRoomSimpleLiveTab: String, CaseIterable, Identifiable {
    case chat
    case info
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "聊天"
        case .info:
            return "直播间"
        case .settings:
            return "设置"
        }
    }
}

/// An iOS-native take on SimpleLive's portrait information architecture. The
/// player surface itself stays outside this view so rotation and decoding are
/// still owned by the existing UIKit coordinator.
private struct LiveRoomSimpleLiveLayoutView: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    @ObservedObject var state: LiveRoomShellContentView.State
    let onNavigateBack: () -> Void

    @State private var selectedTab: LiveRoomSimpleLiveTab = .chat

    private let bottomActionBarHeight: CGFloat = 40

    private var bottomContentReservation: CGFloat {
        bottomActionBarHeight + 16
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                    .frame(
                        height: state.topSafeAreaInset
                            + LiveRoomSimpleLiveLayoutPolicy.headerContentHeight,
                        alignment: .bottom
                    )

                // The UIKit surface covers this placeholder. It makes the
                // SwiftUI detail content follow the true player bottom edge.
                Color.clear
                    .frame(height: state.playerHeight)

                VStack(alignment: .leading, spacing: 12) {
                    anchorSummary
                    sectionPicker
                    selectedContent
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(
                    .bottom,
                    bottomContentReservation + max(state.bottomSafeAreaInset, 0)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(
                width: state.layoutWidth,
                height: state.layoutHeight,
                alignment: .top
            )

            bottomActionBar
                .padding(.horizontal, 12)
                .padding(.bottom, max(state.bottomSafeAreaInset, 10))
        }
        .background(LiveRoomTheme.background)
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onNavigateBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .biliRegularGlassEffect(interactive: true, in: Circle())
            .accessibilityLabel("返回")

            Text(viewModel.title)
                .appTypography(.liveRoomTitle, fallback: .system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("直播间：\(viewModel.title)")

            Menu {
                Button {
                    viewModel.showLiveDanmakuSettings()
                } label: {
                    Label("弹幕设置", systemImage: "text.bubble")
                }

                Button {
                    viewModel.showLivePlaybackDiagnostics()
                } label: {
                    Label("播放诊断", systemImage: "waveform.path.ecg.rectangle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .biliRegularGlassEffect(interactive: true, in: Circle())
            .accessibilityLabel("直播间更多操作")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var anchorSummary: some View {
        HStack(spacing: 10) {
            PlaybackDetailOwnerAvatar(
                owner: viewModel.anchorOwner,
                fallbackURLString: viewModel.anchorFace,
                side: 46,
                pixelSize: 128
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.anchorName)
                    .appTypography(
                        .commentAuthor,
                        fallback: .subheadline.weight(.semibold)
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(liveStatusText)
                    .appTypography(.metadata, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            followButton
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("主播 \(viewModel.anchorName)，\(liveStatusText)")
    }

    private var liveStatusText: String {
        viewModel.isLive ? "\(viewModel.onlineText)  正在直播" : viewModel.onlineText
    }

    private var followButton: some View {
        DetailToolbarFollowButton(
            isFollowing: viewModel.isFollowingAnchor,
            isLoading: viewModel.isMutatingAnchorFollow,
            canFollow: viewModel.anchorUIDForFollow != nil
        ) {
            Task {
                await viewModel.toggleFollowAnchor()
            }
        }
    }

    private var sectionPicker: some View {
        Picker("直播内容", selection: $selectedTab) {
            ForEach(LiveRoomSimpleLiveTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("直播间内容")
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .chat:
            LiveRoomPlainDanmakuTimeline(
                renderState: state.chatTimelineState,
                isDanmakuEnabled: viewModel.isDanmakuEnabled,
                bottomSafeAreaInset: 0,
                additionalBottomInset: bottomContentReservation,
                usesDarkForeground: false,
                onEnableDanmaku: viewModel.toggleDanmaku
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .info:
            LiveRoomSimpleLiveInfoPane(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .settings:
            LiveRoomSimpleLiveSettingsPane(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var bottomActionBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                liveActionButton(
                    title: viewModel.isFollowingAnchor ? "已关注" : "关注",
                    systemImage: viewModel.isFollowingAnchor ? "checkmark" : "plus"
                ) {
                    Task {
                        await viewModel.toggleFollowAnchor()
                    }
                }
                .disabled(viewModel.anchorUIDForFollow == nil || viewModel.isMutatingAnchorFollow)

                liveActionButton(title: "刷新", systemImage: "arrow.clockwise") {
                    viewModel.refreshLiveToLatest()
                }

                liveShareAction
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func liveActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: bottomActionBarHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .biliRegularGlassEffect(interactive: true, in: Capsule())
    }

    @ViewBuilder
    private var liveShareAction: some View {
        if let shareURL = URL(string: "https://live.bilibili.com/\(viewModel.roomID)") {
            ShareLink(
                item: shareURL,
                subject: Text(viewModel.title),
                message: Text("来自哔哩哔哩的直播间")
            ) {
                Label("分享", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: bottomActionBarHeight)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .biliRegularGlassEffect(interactive: true, in: Capsule())
            .accessibilityLabel("分享直播间")
        }
    }
}

private struct LiveRoomSimpleLiveInfoPane: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("直播间信息")
                    .font(.headline)

                detailRow("主播", value: viewModel.anchorName)
                detailRow("热度", value: viewModel.onlineText)

                if let areaText = viewModel.areaText {
                    detailRow("分区", value: areaText)
                }

                if let liveTimeText = viewModel.liveTimeText {
                    detailRow("开播时间", value: liveTimeText)
                }

                if let descriptionText = viewModel.descriptionText {
                    Divider()

                    Text("简介")
                        .font(.subheadline.weight(.semibold))
                    Text(descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LiveRoomSimpleLiveSettingsPane: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("播放") {
                    VStack(spacing: 12) {
                        qualityMenu
                        if viewModel.hasMultipleStreamCandidates || viewModel.currentStreamTitle != nil {
                            Divider()
                            streamMenu
                        }
                        Divider()
                        Button {
                            viewModel.showLivePlaybackDiagnostics()
                        } label: {
                            Label("播放诊断", systemImage: "waveform.path.ecg.rectangle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }

                GroupBox("弹幕") {
                    VStack(spacing: 12) {
                        Toggle("显示滚动弹幕", isOn: danmakuEnabledBinding)

                        Toggle(
                            "竖屏时隐藏弹幕",
                            isOn: Binding(
                                get: { viewModel.danmakuSettings.hidesInPortrait },
                                set: { viewModel.setDanmakuHidesInPortrait($0) }
                            )
                        )

                        Divider()

                        Button {
                            viewModel.showLiveDanmakuSettings()
                        } label: {
                            Label("打开弹幕设置", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var danmakuEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isDanmakuEnabled },
            set: { shouldEnable in
                guard shouldEnable != viewModel.isDanmakuEnabled else { return }
                viewModel.toggleDanmaku()
            }
        )
    }

    @ViewBuilder
    private var qualityMenu: some View {
        if viewModel.hasMultipleQualities || viewModel.currentQualityTitle != nil {
            HStack(spacing: 12) {
                Label("画质", systemImage: "slider.horizontal.3")
                Spacer(minLength: 12)
                Menu {
                    ForEach(viewModel.qualityMenuItems) { item in
                        Button {
                            viewModel.selectQuality(qn: item.qn)
                        } label: {
                            Label(item.title, systemImage: item.isSelected ? "checkmark" : "")
                        }
                    }
                } label: {
                    Text(viewModel.currentQualityTitle ?? "自动")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var streamMenu: some View {
        HStack(spacing: 12) {
            Label("线路", systemImage: "antenna.radiowaves.left.and.right")
            Spacer(minLength: 12)
            Menu {
                ForEach(viewModel.streamMenuItems) { item in
                    Button {
                        viewModel.selectStreamCandidate(id: item.id)
                    } label: {
                        Label(item.title, systemImage: item.isSelected ? "checkmark" : "")
                    }
                }
            } label: {
                Text(viewModel.currentStreamTitle ?? "自动")
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct LiveDanmakuShellDiagnosticsOverlay: View {
    @ObservedObject var store: LiveDanmakuDiagnosticsStore

    var body: some View {
        LiveDanmakuDiagnosticsHUD(snapshot: store.snapshot, isExpanded: false)
            .allowsHitTesting(false)
    }
}

private struct LiveRoomPortraitHeader: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    let onNavigateBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onNavigateBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .contentShape(Circle())
            .biliRegularGlassEffect(interactive: true, in: Circle())
            .accessibilityLabel("返回")

            PlaybackDetailOwnerAvatar(
                owner: viewModel.anchorOwner,
                fallbackURLString: viewModel.anchorFace,
                side: 42,
                pixelSize: 128
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.anchorName)
                    .appTypography(
                        .commentAuthor,
                        fallback: .subheadline.weight(.semibold)
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(liveStatusText)
                    .appTypography(.metadata, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            followButton
        }
        .padding(.horizontal, 10)
        .background(LiveRoomTheme.background)
    }

    private var liveStatusText: String {
        if viewModel.isLive {
            return "\(viewModel.onlineText)  正在直播"
        }
        return viewModel.onlineText
    }

    private var followButton: some View {
        DetailToolbarFollowButton(
            isFollowing: viewModel.isFollowingAnchor,
            isLoading: viewModel.isMutatingAnchorFollow,
            canFollow: viewModel.anchorUIDForFollow != nil
        ) {
            Task {
                await viewModel.toggleFollowAnchor()
            }
        }
    }
}

private struct LiveRoomDanmakuTimeline: View {
    @ObservedObject var renderState: LiveRoomChatTimelineState
    let isDanmakuEnabled: Bool
    let bottomSafeAreaInset: CGFloat
    let onEnableDanmaku: () -> Void
    @State private var followsLatest = true

    private var visibleItems: ArraySlice<DanmakuItem> {
        renderState.snapshot.items.suffix(120)
    }

    var body: some View {
        let snapshot = renderState.snapshot
        ZStack(alignment: .bottomTrailing) {
            if !isDanmakuEnabled || !snapshot.isEnabled {
                Button(action: onEnableDanmaku) {
                    Label("开启弹幕", systemImage: "text.bubble")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("开启直播弹幕")
            } else if visibleItems.isEmpty {
                LiveRoomDanmakuEmptyState(
                    phase: snapshot.connectionPhase,
                    error: snapshot.connectionError,
                    isLoadingHistory: snapshot.isLoadingHistory,
                    historyError: snapshot.historyError
                )
            } else {
                timeline
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiveRoomTheme.background)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(visibleItems) { item in
                        LiveRoomDanmakuBubble(
                            item: item
                        )
                            .id(item.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(
                    .bottom,
                    bottomSafeAreaInset + LiveRoomChatLayoutMetrics.chatOverlaySpacing
                )
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        followsLatest = false
                    }
            )
            .onAppear {
                scrollToLatest(using: proxy)
            }
            .onChange(of: renderState.snapshot.itemsRevision) { _, _ in
                guard followsLatest else { return }
                scrollToLatest(using: proxy)
            }
            .overlay(alignment: .bottomTrailing) {
                if !followsLatest {
                    Button {
                        followsLatest = true
                        scrollToLatest(using: proxy)
                    } label: {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .contentShape(Circle())
                    .biliRegularGlassEffect(interactive: true, in: Circle())
                    .padding(.trailing, 16)
                    .padding(
                        .bottom,
                        bottomSafeAreaInset + 4
                    )
                    .accessibilityLabel("回到最新弹幕")
                }
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let latestID = visibleItems.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(latestID, anchor: .bottom)
        }
    }
}

private struct LiveRoomDanmakuEmptyState: View {
    let phase: LiveDanmakuDiagnosticPhase
    let error: String?
    let isLoadingHistory: Bool
    let historyError: String?

    var body: some View {
        VStack(spacing: 10) {
            if showsLoadingIndicator {
                ProgressView()
                    .tint(foregroundColor)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(foregroundColor)
            }

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(primaryTextColor)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(foregroundColor)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var showsLoadingIndicator: Bool {
        if isLoadingHistory {
            return true
        }
        switch phase {
        case .idle, .fetchingConfig, .connecting, .authenticating:
            return true
        case .waitingForPackets, .receiving, .rendering, .reconnecting, .stopped, .failed:
            return false
        }
    }

    private var systemImage: String {
        switch phase {
        case .reconnecting:
            return "arrow.clockwise"
        case .failed:
            return "exclamationmark.triangle"
        case .stopped:
            return "pause.circle"
        case .waitingForPackets, .receiving, .rendering:
            return "text.bubble"
        case .idle, .fetchingConfig, .connecting, .authenticating:
            return "text.bubble"
        }
    }

    private var title: String {
        if isLoadingHistory {
            return "正在加载最近弹幕"
        }
        if historyError != nil {
            return "最近弹幕暂时无法加载"
        }
        switch phase {
        case .waitingForPackets, .receiving, .rendering:
            return "暂时没有新弹幕"
        case .reconnecting:
            return "弹幕正在重新连接"
        case .failed:
            return "弹幕暂时不可用"
        case .stopped:
            return "弹幕已暂停"
        case .idle, .fetchingConfig, .connecting, .authenticating:
            return "正在连接直播弹幕"
        }
    }

    private var subtitle: String? {
        if historyError != nil {
            return "实时弹幕仍会继续接收"
        }
        switch phase {
        case .reconnecting:
            return error?.nilIfEmpty ?? "网络恢复后会继续显示"
        case .failed:
            return error?.nilIfEmpty ?? "请稍后再试"
        default:
            return nil
        }
    }

    private var accessibilityLabel: String {
        [title, subtitle]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    private var primaryTextColor: Color {
        .primary
    }

    private var foregroundColor: Color {
        .secondary
    }
}

private struct LiveRoomDanmakuBubble: View {
    let item: DanmakuItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let senderName {
                Text(senderName)
                    .appTypography(.liveChatName, fallback: .caption.weight(.semibold))
                    .foregroundStyle(senderColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 4)
            }

            messageContent
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(bubbleBackground, in: IncomingMessageBubbleShape())
                .frame(maxWidth: 320, alignment: .leading)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }

    private var senderName: String? {
        guard let name = item.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return name
    }

    private var bubbleBackground: Color {
        return item.mode == 5 ? LiveRoomTheme.highlightedChatBubble : LiveRoomTheme.chatBubble
    }

    @ViewBuilder
    private var messageContent: some View {
        if item.inlineEmotes.isEmpty {
            Text(item.text)
                .appTypography(.liveChatBody, fallback: .body)
                .foregroundStyle(messageColor)
        } else {
            BiliEmoteText(
                content: nil,
                plainText: item.text,
                inlineEmotes: item.inlineEmotes,
                font: .body,
                textColor: messageColor,
                emoteSize: 26,
                showsLinkButtons: false,
                fillsAvailableWidth: false,
                typographyRole: .liveChatBody
            )
        }
    }

    private var senderColor: Color {
        return item.mode == 5 ? LiveRoomTheme.highlightedChatSender : LiveRoomTheme.chatSender
    }

    private var messageColor: Color {
        .primary
    }

    private var accessibilityLabel: String {
        if let senderName {
            return "直播弹幕，\(senderName)：\(item.text)"
        }
        return "直播弹幕：\(item.text)"
    }
}

/// 左侧收到消息的非对称圆角，接近系统信息的气泡比例，并避免长弹幕占满整行。
private struct IncomingMessageBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 5,
            bottomTrailingRadius: 18,
            topTrailingRadius: 18,
            style: .continuous
        )
        .path(in: rect)
    }

}
