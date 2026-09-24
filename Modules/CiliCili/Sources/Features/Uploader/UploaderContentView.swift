import SwiftUI

struct UploaderContentView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    let owner: VideoOwner
    @ObservedObject var viewModel: UploaderViewModel
    let allowsPullToRefresh: Bool
    let showsToolbarRefreshButton: Bool

    @State private var contentWidth: CGFloat = 0
    @State private var selectedSection: UploaderProfileSection
    @State private var isRefreshingFromToolbar = false
    @State private var pullRefreshDistance: CGFloat = 0
    @State private var isConfiguredPullRefreshing = false
    @State private var pullRefreshActions = HomeFeedRefreshActions()

    init(
        owner: VideoOwner,
        viewModel: UploaderViewModel,
        allowsPullToRefresh: Bool = true,
        showsToolbarRefreshButton: Bool = false
    ) {
        self.owner = owner
        self.viewModel = viewModel
        self.allowsPullToRefresh = allowsPullToRefresh
        self.showsToolbarRefreshButton = showsToolbarRefreshButton
        _selectedSection = State(initialValue: Self.initialSection)
    }

    @ViewBuilder
    var body: some View {
        if showsToolbarRefreshButton {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        toolbarRefreshButton
                    }
                }
        } else {
            content
        }
    }

    private var content: some View {
        scrollContent
            .task {
                await viewModel.loadInitial()
            }
            .task(id: selectedSection) {
                switch selectedSection {
                case .videos:
                    break
                case .dynamics:
                    await viewModel.loadDynamicsIfNeeded()
                case .collections:
                    await viewModel.loadSeasonSeriesIfNeeded()
                }
            }
    }

    @ViewBuilder
    private var scrollContent: some View {
        if allowsPullToRefresh {
            baseScrollContent
                .nativePullRefresh(
                    isEnabled: libraryStore.usesNativePullRefresh,
                    action: refreshSelectedSection
                )
                .homeFeedPullRefreshLayout(
                    pullDistance: pullRefreshDistance,
                    triggerDistance: CGFloat(libraryStore.homeRefreshTriggerDistance),
                    isRefreshing: isConfiguredPullRefreshing,
                    isEnabled: libraryStore.usesCustomPullRefresh
                )
        } else {
            baseScrollContent
        }
    }

    private var baseScrollContent: some View {
        ScrollView {
            UploaderContentWidthReader()

            VStack(alignment: .leading, spacing: 18) {
                UploaderHeaderView(owner: owner, viewModel: viewModel)

                Picker("内容", selection: $selectedSection) {
                    ForEach(UploaderProfileSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)

                selectedContent
            }
            .padding(.vertical, 12)
        }
        .onPreferenceChange(UploaderContentWidthPreferenceKey.self, perform: updateContentWidth)
        .customPullRefreshTracking(
            isEnabled: allowsPullToRefresh && libraryStore.usesCustomPullRefresh,
            onChange: handlePullRefreshChange
        )
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .videos:
            UploaderVideosSection(
                viewModel: viewModel,
                metrics: HomeFeedLayoutMetrics(mode: .doubleColumn, containerWidth: contentWidth)
            )
        case .dynamics:
            UploaderDynamicsSection(
                api: dependencies.api,
                viewModel: viewModel,
                contentWidth: contentWidth
            )
        case .collections:
            UploaderSeasonSeriesSection(viewModel: viewModel)
        }
    }

    private func refreshSelectedSection() async {
        switch selectedSection {
        case .videos:
            await viewModel.refresh()
        case .dynamics:
            await viewModel.refreshDynamics()
        case .collections:
            await viewModel.refreshSeasonSeries()
        }
    }

    private func handlePullRefreshChange(
        pullDistance: CGFloat,
        isUserInteracting: Bool
    ) {
        pullRefreshDistance = pullDistance
        guard allowsPullToRefresh,
              libraryStore.usesCustomPullRefresh
        else { return }
        pullRefreshActions.handleConfiguredPullRefresh(
            pullDistance: pullDistance,
            triggerDistance: CGFloat(libraryStore.homeRefreshTriggerDistance),
            isUserInteracting: isUserInteracting,
            isRefreshing: isConfiguredPullRefreshing
        ) {
            isConfiguredPullRefreshing = true
            defer { isConfiguredPullRefreshing = false }
            await refreshSelectedSection()
            return selectedSectionState == .loaded
        }
    }

    private var selectedSectionState: LoadingState {
        switch selectedSection {
        case .videos:
            return viewModel.state
        case .dynamics:
            return viewModel.dynamicState
        case .collections:
            return viewModel.seasonSeriesState
        }
    }

    private var toolbarRefreshButton: some View {
        Button {
            refreshFromToolbar()
        } label: {
            Group {
                if isRefreshingFromToolbar {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 32, height: 32)
        }
        .disabled(isRefreshingFromToolbar)
        .buttonBorderShape(.circle)
        .biliGlassButtonStyle()
        .accessibilityLabel("刷新个人空间")
    }

    private func refreshFromToolbar() {
        guard !isRefreshingFromToolbar else { return }
        isRefreshingFromToolbar = true
        Task {
            await refreshSelectedSection()
            isRefreshingFromToolbar = false
        }
    }

    private func updateContentWidth(_ width: CGFloat) {
        let roundedWidth = width.rounded(.down)
        guard abs(roundedWidth - contentWidth) > 0.5 else { return }
        contentWidth = roundedWidth
    }

    private static var initialSection: UploaderProfileSection {
        guard let value = argumentValue(after: "--start-uploader-section") else { return .videos }
        return UploaderProfileSection(argumentValue: value) ?? .videos
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        let value = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private enum UploaderProfileSection: String, CaseIterable, Identifiable {
    case videos
    case dynamics
    case collections

    var id: String { rawValue }

    init?(argumentValue: String) {
        switch argumentValue.lowercased() {
        case "video", "videos", "archive", "archives":
            self = .videos
        case "dynamic", "dynamics":
            self = .dynamics
        case "collection", "collections", "season", "seasons", "series":
            self = .collections
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .videos:
            return "投稿"
        case .dynamics:
            return "动态"
        case .collections:
            return "合集"
        }
    }
}
