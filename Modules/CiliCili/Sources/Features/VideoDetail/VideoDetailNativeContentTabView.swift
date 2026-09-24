import SwiftUI

struct VideoDetailNativeContentTabView<Content: View>: View {
    private let segmentedPickerHeight: CGFloat = 40
    @Environment(\.appThemeTintColor) private var appTintColor
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var bottomInset: CGFloat = 0
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let mountsSecondaryContent: Bool
    var hidesBottomToolbar = false
    var placesTopInsetInScrollContent = false
    var interactiveMinimumPlayerHeight = VideoDetailShellLayout.collapsedToolbarHeight
    var contentRevision: Int = 0
    var onOpenCommentComposer: (() -> Void)?
    var onRefreshComments: () -> Void = {}
    var onSelectionWillChange: ((VideoDetailContentTab) -> Void)? = nil
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    var onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)? = nil
    var summary: AnyView? = nil
    let content: (VideoDetailContentTab, Bool) -> Content

    var body: some View {
        Group {
            if placesTopInsetInScrollContent {
                tabContent
            } else {
                VStack(spacing: 0) {
                    Color.clear.frame(height: topInset).accessibilityHidden(true)
                    tabContent
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar {
            if onOpenCommentComposer != nil {
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Group {
                        if selection == .comments {
                            VideoDetailToolbarCommentRefreshButton(action: onRefreshComments)
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                        } else {
                            Color.clear
                                .frame(
                                    width: VideoDetailToolbarCommentComposerButton.size,
                                    height: VideoDetailToolbarCommentComposerButton.size
                                )
                        }
                    }
                    .animation(.smooth(duration: 0.22), value: selection)
                    .allowsHitTesting(selection == .comments)
                    .accessibilityHidden(selection != .comments)
                }
                .sharedBackgroundVisibility(selection == .comments ? .automatic : .hidden)
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    VideoDetailToolbarSegmentedPickerView(selection: toolbarSelection)
                        .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Group {
                        if selection == .comments, let onOpenCommentComposer {
                            VideoDetailToolbarCommentComposerButton(action: onOpenCommentComposer)
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                        } else {
                            Color.clear
                                .frame(
                                    width: VideoDetailToolbarCommentComposerButton.size,
                                    height: VideoDetailToolbarCommentComposerButton.size
                                )
                        }
                    }
                    .animation(.smooth(duration: 0.22), value: selection)
                    .allowsHitTesting(selection == .comments)
                    .accessibilityHidden(selection != .comments)
                }
                .sharedBackgroundVisibility(selection == .comments ? .automatic : .hidden)
                ToolbarSpacer(.flexible, placement: .bottomBar)
            } else {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer(minLength: 0)
                    VideoDetailToolbarSegmentedPickerView(selection: toolbarSelection)
                        .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
                    Spacer(minLength: 0)
                }
            }
        }
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbarVisibility(hidesBottomToolbar ? .hidden : .visible, for: .bottomBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .tint(appTintColor)
    }

    private var tabContent: some View {
        ZStack {
            ForEach(VideoDetailContentTab.allCases) { tab in
                page(for: tab)
                    .opacity(selection == tab ? 1 : 0)
                    .allowsHitTesting(selection == tab)
                    .accessibilityHidden(selection != tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.smooth(duration: 0.28), value: selection)
        .background(VideoDetailTheme.background)
    }

    private var toolbarSelection: Binding<VideoDetailContentTab> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard newSelection != selection else { return }
                onSelectionWillChange?(newSelection)
                selection = newSelection
            }
        )
    }

    @ViewBuilder
    private func page(for tab: VideoDetailContentTab) -> some View {
        let pageContent = {
            content(
                tab,
                mountsSecondaryContent || (tab == .comments && selection == .comments)
            )
        }
        if placesTopInsetInScrollContent {
            VideoDetailInteractiveScrollingTabPage(
                tab: tab,
                scrollAdjustment: scrollAdjustment,
                onScrollOffsetChange: onScrollOffsetChange,
                onScrollPhaseChange: onScrollPhaseChange,
                summary: tab == .detail ? summary : nil,
                topInset: topInset,
                minimumPlayerHeight: interactiveMinimumPlayerHeight,
                contentRevision: contentRevision,
                contentMountsSecondaryContent: mountsSecondaryContent
                    || (tab == .comments && selection == .comments),
                bottomInset: bottomInset + segmentedPickerHeight + 16,
                content: pageContent
            )
        } else {
            VideoDetailScrollingTabPage(
                tab: tab,
                scrollAdjustment: scrollAdjustment,
                onScrollOffsetChange: onScrollOffsetChange,
                onScrollPhaseChange: onScrollPhaseChange,
                summary: tab == .detail ? summary : nil,
                topInset: 0,
                minimumPlayerHeight: 0,
                bottomInset: bottomInset + segmentedPickerHeight + 16,
                content: { _ in pageContent() }
            )
        }
    }
}

@MainActor
private struct VideoDetailInteractiveScrollingTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
    let summary: AnyView?
    let topInset: CGFloat
    let minimumPlayerHeight: CGFloat
    let contentRevision: Int
    let contentMountsSecondaryContent: Bool
    let bottomInset: CGFloat
    let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            VideoDetailInteractiveScrollHost(
                tab: tab,
                viewportHeight: proxy.size.height,
                scrollAdjustment: scrollAdjustment,
                onScrollOffsetChange: onScrollOffsetChange,
                onScrollPhaseChange: onScrollPhaseChange,
                summary: summary,
                topInset: topInset,
                minimumPlayerHeight: minimumPlayerHeight,
                contentRevision: contentRevision,
                contentMountsSecondaryContent: contentMountsSecondaryContent,
                bottomInset: bottomInset,
                content: content
            )
        }
    }
}

@MainActor
private struct VideoDetailInteractiveScrollHost<Content: View>: UIViewRepresentable {
    let tab: VideoDetailContentTab
    let viewportHeight: CGFloat
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
    let summary: AnyView?
    let topInset: CGFloat
    let minimumPlayerHeight: CGFloat
    let contentRevision: Int
    let contentMountsSecondaryContent: Bool
    let bottomInset: CGFloat
    let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = context.coordinator

        let hostingController = UIHostingController(rootView: scrollContent)
        hostingController.sizingOptions = .intrinsicContentSize
        hostingController.safeAreaRegions = []
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        context.coordinator.hostingController = hostingController
        context.coordinator.update(
            scrollView: scrollView,
            tab: tab,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            onScrollPhaseChange: onScrollPhaseChange,
            bottomInset: bottomInset,
            contentConfiguration: contentConfiguration
        )
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let contentChanged = context.coordinator.contentConfiguration != contentConfiguration
        if contentChanged {
            context.coordinator.hostingController?.rootView = scrollContent
            context.coordinator.contentConfiguration = contentConfiguration
        }
        context.coordinator.update(
            scrollView: scrollView,
            tab: tab,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            onScrollPhaseChange: onScrollPhaseChange,
            bottomInset: bottomInset,
            contentConfiguration: contentConfiguration
        )
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        scrollView.delegate = nil
        coordinator.hostingController?.view.removeFromSuperview()
        coordinator.hostingController = nil
    }

    private var scrollContent: AnyView {
        return AnyView(
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topInset)
                    .accessibilityHidden(true)
                LazyVStack(spacing: 12) {
                    summary
                    content()
                }
                .padding(.top, 12)
            }
            .frame(
                minHeight: VideoDetailShellLayout.scrollContentMinimumHeight(
                    viewportHeight: viewportHeight,
                    expandedPlayerHeight: topInset,
                    minimumPlayerHeight: minimumPlayerHeight
                ),
                alignment: .top
            )
            .environment(
                \.videoDetailCommentsEmptyStateMinimumHeight,
                max(viewportHeight - bottomInset, 0)
            )
        )
    }

    private var contentConfiguration: ContentConfiguration {
        ContentConfiguration(
            viewportHeight: viewportHeight,
            topInset: topInset,
            minimumPlayerHeight: minimumPlayerHeight,
            contentRevision: contentRevision,
            contentMountsSecondaryContent: contentMountsSecondaryContent
        )
    }

    fileprivate struct ContentConfiguration: Equatable {
        let viewportHeight: CGFloat
        let topInset: CGFloat
        let minimumPlayerHeight: CGFloat
        let contentRevision: Int
        let contentMountsSecondaryContent: Bool
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>?
        fileprivate var contentConfiguration: ContentConfiguration?
        private var tab: VideoDetailContentTab?
        private var onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
        private var onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
        private var appliedScrollAdjustmentToken: Int?
        private var isApplyingScrollAdjustment = false
        private var virtualScrollOffset: CGFloat = 0
        private var lastReportedVirtualScrollOffset: CGFloat?
        private var pendingReportedScroll: (tab: VideoDetailContentTab, offset: CGFloat)?
        private var isReportScheduled = false
        private var hasUserScrolled = false
        private var isUpdatingView = false

        fileprivate func update(
            scrollView: UIScrollView,
            tab: VideoDetailContentTab,
            scrollAdjustment: VideoDetailScrollAdjustment?,
            onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?,
            onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?,
            bottomInset: CGFloat,
            contentConfiguration: ContentConfiguration
        ) {
            isUpdatingView = true
            defer { isUpdatingView = false }
            let tabChanged = self.tab != tab
            self.tab = tab
            self.onScrollOffsetChange = onScrollOffsetChange
            self.onScrollPhaseChange = onScrollPhaseChange
            self.contentConfiguration = contentConfiguration
            if tabChanged {
                lastReportedVirtualScrollOffset = nil
                pendingReportedScroll = nil
            }
            let resolvedBottomInset = max(bottomInset, 0)
            if scrollView.contentInset.bottom != resolvedBottomInset {
                scrollView.contentInset.bottom = resolvedBottomInset
                scrollView.verticalScrollIndicatorInsets.bottom = resolvedBottomInset
            }

            if !scrollView.isTracking && !scrollView.isDecelerating {
                applyVirtualScrollOffset(virtualScrollOffset, to: scrollView)
            }

            guard let scrollAdjustment,
                  scrollAdjustment.tab == tab,
                  appliedScrollAdjustmentToken != scrollAdjustment.token
            else { return }
            appliedScrollAdjustmentToken = scrollAdjustment.token
            applyVirtualScrollOffset(scrollAdjustment.offset, to: scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard let tab else { return }
            hasUserScrolled = true
            onScrollPhaseChange?(tab, .tracking)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isApplyingScrollAdjustment, let tab else { return }

            guard hasUserScrolled else {
                applyVirtualScrollOffset(0, to: scrollView)
                return
            }

            virtualScrollOffset = max(0, scrollView.contentOffset.y)

            reportScrollOffset(
                tab: tab,
                offset: virtualScrollOffset,
                immediately: !isUpdatingView && (scrollView.isDragging || scrollView.isDecelerating)
            )
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard let tab else { return }
            onScrollPhaseChange?(tab, decelerate ? .decelerating : .idle)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let tab else { return }
            applyVirtualScrollOffset(max(0, scrollView.contentOffset.y), to: scrollView)
            if hasUserScrolled {
                reportScrollOffset(tab: tab, offset: virtualScrollOffset)
            }
            onScrollPhaseChange?(tab, .idle)
        }

        private func applyVirtualScrollOffset(
            _ offset: CGFloat,
            to scrollView: UIScrollView
        ) {
            let normalizedOffset = max(offset, 0)
            virtualScrollOffset = normalizedOffset
            let contentOffset = normalizedOffset

            guard abs(scrollView.contentOffset.y - contentOffset) > 0.5 else { return }
            isApplyingScrollAdjustment = true
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: contentOffset),
                animated: false
            )
            isApplyingScrollAdjustment = false
        }

        private func reportScrollOffset(
            tab: VideoDetailContentTab,
            offset: CGFloat,
            immediately: Bool = false
        ) {
            guard lastReportedVirtualScrollOffset.map({ abs($0 - offset) > 0.5 }) ?? true else {
                return
            }
            lastReportedVirtualScrollOffset = offset
            if immediately {
                pendingReportedScroll = nil
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    onScrollOffsetChange?(tab, offset)
                }
                return
            }
            pendingReportedScroll = (tab, offset)
            guard !isReportScheduled else { return }
            isReportScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReportScheduled = false
                guard let report = self.pendingReportedScroll
                else { return }
                self.pendingReportedScroll = nil
                guard self.tab == report.tab else { return }
                self.onScrollOffsetChange?(report.tab, report.offset)
            }
        }
    }
}

private struct VideoDetailScrollingTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
    let summary: AnyView?
    let topInset: CGFloat
    let minimumPlayerHeight: CGFloat
    let bottomInset: CGFloat
    @ViewBuilder let content: (VideoDetailContentTab) -> Content
    @State private var position = ScrollPosition()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                scrollStack
                .padding(.top, 12)
                .frame(
                    minHeight: minimumScrollableContentHeight(viewportHeight: proxy.size.height),
                    alignment: .top
                )
            }
            .environment(
                \.videoDetailCommentsEmptyStateMinimumHeight,
                topInset > 0 ? max(proxy.size.height - bottomInset, 0) : 0
            )
            .scrollPosition($position)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .scrollIndicators(.hidden)
            .nativeTopScrollEdgeEffect()
            .onScrollGeometryChange(for: CGFloat.self) {
                max(0, $0.contentOffset.y + $0.contentInsets.top)
            } action: { _, offset in
                onScrollOffsetChange?(tab, offset)
            }
            .onScrollPhaseChange { _, phase in
                onScrollPhaseChange?(tab, phase)
            }
            .onChange(of: scrollAdjustment) { _, adjustment in
                guard let adjustment, adjustment.tab == tab else { return }
                position.scrollTo(y: adjustment.offset)
            }
        }
    }

    private func minimumScrollableContentHeight(viewportHeight: CGFloat) -> CGFloat {
        VideoDetailShellLayout.scrollContentMinimumHeight(
            viewportHeight: viewportHeight,
            expandedPlayerHeight: topInset,
            minimumPlayerHeight: minimumPlayerHeight
        )
    }

    @ViewBuilder
    private var scrollStack: some View {
        if topInset > 0, minimumPlayerHeight > 0 {
            LazyVStack(spacing: 12) {
                Color.clear
                    .frame(height: topInset)
                    .accessibilityHidden(true)
                summary
                content(tab)
            }
        } else {
            LazyVStack(spacing: 12) {
                summary
                content(tab)
            }
        }
    }
}

private struct VideoDetailToolbarCommentComposerButton: View {
    static let size: CGFloat = 38

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .frame(width: Self.size, height: Self.size)
        }
        .tint(.primary)
        .accessibilityLabel("发表评论")
        .accessibilityIdentifier("video.detail.toolbar-comment-compose")
    }
}

private struct VideoDetailToolbarCommentRefreshButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .frame(
                    width: VideoDetailToolbarCommentComposerButton.size,
                    height: VideoDetailToolbarCommentComposerButton.size
                )
        }
        .tint(.primary)
        .accessibilityLabel("刷新评论")
        .accessibilityIdentifier("video.detail.toolbar-comment-refresh")
    }
}
