import SwiftUI

struct SearchListView: View {
    @ObservedObject var viewModel: SearchViewModel
    let showsHotSearches: Bool

    private let discoveryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if viewModel.showsDiscovery {
                    discoveryContent
                } else if viewModel.results.isEmpty && viewModel.state.isLoading {
                    SearchLoadingContent(scope: viewModel.selectedScope)
                } else if viewModel.showsEmptyResults {
                    emptyResultsView
                } else {
                    resultsContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .scrollBounceBehavior(.always, axes: .vertical)
        .defersRemoteImageLoadsDuringFastScroll()
        .background(Color(.systemGroupedBackground))
        .nativeTopScrollEdgeEffect()
    }

    @ViewBuilder
    private var discoveryContent: some View {
        if viewModel.showsSuggestions {
            SearchContentSection(title: "搜索建议", systemImage: "sparkle.magnifyingglass") {
                VStack(spacing: 0) {
                    ForEach(viewModel.suggestions.prefix(8)) { item in
                        SearchSuggestionRow(item: item) {
                            Task { await viewModel.searchSuggestion(item) }
                        }
                    }
                }
            }
        } else {
            if !showsHotSearches {
                SearchDiscoveryEmptyCard(title: "开始搜索", message: "输入关键词后搜索内容。")
            } else if viewModel.hotSearchState.isLoading {
                SearchDiscoveryLoadingCard()
            } else if viewModel.hotSearches.isEmpty {
                SearchDiscoveryEmptyCard(title: "暂无热门搜索", message: "输入关键词后搜索。")
            } else {
                SearchContentSection(title: "大家都在搜", systemImage: "flame.fill") {
                    LazyVGrid(columns: discoveryColumns, alignment: .leading, spacing: 10) {
                        ForEach(displayedHotSearches) { item in
                            SearchDiscoveryChip(item: item) {
                                Task { await viewModel.searchHotSearch(item) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        ForEach(viewModel.results) { result in
            if shouldShowSectionHeader(for: result) {
                Label(result.sectionTitle, systemImage: result.sectionSystemImage)
                    .font(.headline)
                    .padding(.top, result == viewModel.results.first ? 0 : 8)
            }

            SearchStructuredResultCard(result: result)
                .equatable()
        }

        if let lastResult = viewModel.results.last {
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
                .task(id: lastResult.id) {
                    await viewModel.loadMoreIfNeeded(current: lastResult)
                }
        }

        if viewModel.state.isLoading {
            SearchLoadingContent(scope: viewModel.selectedScope, count: 4, showsTitle: false)
        }
    }

    private var displayedHotSearches: [HotSearchItem] {
        Array(viewModel.hotSearches.prefix(10))
    }

    private func shouldShowSectionHeader(for result: SearchResultItem) -> Bool {
        guard viewModel.selectedScope == .comprehensive else { return false }
        guard let index = viewModel.results.firstIndex(of: result) else { return false }
        guard index > 0 else { return true }
        return viewModel.results[index - 1].sectionTitle != result.sectionTitle
    }

    private var emptyResultsView: some View {
        EmptyStateView(
            title: viewModel.emptyResultsTitle,
            systemImage: viewModel.selectedScope.systemImage,
            message: "换个关键词或切换搜索类型试试。"
        )
        .padding(.top, 10)
    }

}

private struct SearchSuggestionRow: View {
    let item: SearchSuggestItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(item.value)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.left")
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索建议：\(item.value)")
    }
}

private struct SearchContentSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SearchDiscoveryChip: View {
    let item: HotSearchItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(item.showName ?? item.keyword)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("热门搜索，\(item.showName ?? item.keyword)")
    }
}

private struct SearchDiscoveryLoadingCard: View {
    var body: some View {
        SearchContentSection(title: "大家都在搜", systemImage: "flame.fill") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(0..<10, id: \.self) { _ in
                    SkeletonBlock(height: 44, shape: .rounded(14))
                }
            }
        }
        .accessibilityLabel("正在加载热门搜索")
    }
}

private struct SearchDiscoveryEmptyCard: View {
    let title: String
    let message: String

    var body: some View {
        EmptyStateView(title: title, systemImage: "magnifyingglass", message: message)
            .padding(.top, 10)
    }
}

private struct SearchStructuredResultCard: View, Equatable {
    let result: SearchResultItem

    var body: some View {
        Group {
            switch result {
            case .video(let video):
                VideoRouteLink(video) {
                    SearchVideoResultRow(video: video)
                }
            default:
                SearchResultRouteRow(result: result)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .compactVideoResultSurface(cornerRadius: 18)
                    .buttonStyle(.plain)
            }
        }
    }
}

struct SearchLoadingContent: View {
    var scope: SearchScope = .comprehensive
    var count = 8
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: showsTitle ? 16 : 12) {
            if showsTitle {
                Label("正在搜索", systemImage: "magnifyingglass")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
            }

            ForEach(0..<count, id: \.self) { _ in
                SearchScopedResultSkeletonRow(scope: scope)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SearchScopedResultSkeletonRow: View {
    let scope: SearchScope

    var body: some View {
        switch scope {
        case .user:
            SearchNonVideoResultSkeletonRow(style: .user)
        case .bangumi, .movie:
            SearchNonVideoResultSkeletonRow(style: .media)
        case .article:
            SearchNonVideoResultSkeletonRow(style: .article)
        case .comprehensive, .video:
            SearchVideoResultSkeletonRow()
        }
    }
}

private struct SearchNonVideoResultSkeletonRow: View {
    enum Style {
        case user
        case media
        case article
    }

    let style: Style
    private let cornerRadius: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingBlock
            textColumn
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .compactVideoResultSurface(cornerRadius: cornerRadius)
        .allowsHitTesting(false)
        .accessibilityLabel("正在加载搜索结果")
    }

    @ViewBuilder
    private var leadingBlock: some View {
        switch style {
        case .user:
            SkeletonBlock(width: 54, height: 54, shape: .circle)
        case .media:
            SkeletonBlock(width: 76, height: 102, shape: .rounded(10))
        case .article:
            SkeletonBlock(width: 78, height: 78, shape: .rounded(8))
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(width: 132, height: 15, shape: .rounded(5))

            switch style {
            case .user:
                SkeletonBlock(width: 188, height: 12, shape: .capsule)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    SkeletonBlock(width: 62, height: 11, shape: .capsule)
                    SkeletonBlock(width: 72, height: 11, shape: .capsule)
                }
            case .media:
                SkeletonBlock(width: 92, height: 18, shape: .capsule)
                SkeletonBlock(width: 150, height: 11, shape: .capsule)
                SkeletonBlock(height: 12, shape: .rounded(5))
                SkeletonBlock(width: 180, height: 12, shape: .rounded(5))
            case .article:
                SkeletonBlock(width: 168, height: 15, shape: .rounded(5))
                SkeletonBlock(width: 112, height: 11, shape: .capsule)
                SkeletonBlock(height: 11, shape: .rounded(5))
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: minimumHeight,
            alignment: .topLeading
        )
    }

    private var minimumHeight: CGFloat {
        switch style {
        case .user:
            return 58
        case .media:
            return 102
        case .article:
            return 78
        }
    }

}
