import SwiftUI

struct VideoDetailPgcEpisodeSection<ActionContent: View>: View {
    let detail: VideoItem
    let selectEpisode: (VideoItem) -> Void
    @ViewBuilder let actionContent: () -> ActionContent

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var season: PgcSeasonInfo?
    @State private var state: LoadingState = .idle
    @State private var order: VideoDetailPgcEpisodeOrder = .ascending
    @State private var isEpisodeSheetPresented = false

    private var loadID: String {
        "\(detail.pgcSeasonID ?? 0)-\(resolvedEpisodeID ?? 0)"
    }

    private var resolvedEpisodeID: Int? {
        detail.pgcEpisodeID ?? detail.bvid.pgcRouteEpisodeID
    }

    var body: some View {
        Group {
            if let season {
                VStack(alignment: .leading, spacing: 18) {
                    VideoDetailPgcSeasonInfoBlock(
                        season: season,
                        detail: detail
                    )

                    actionContent()

                    VideoDetailPgcEpisodeLoadedSection(
                        detail: detail,
                        season: season,
                        selectEpisode: selectEpisode,
                        order: $order,
                        showsEpisodeSheet: $isEpisodeSheetPresented
                    )
                }
            } else if state == .idle || state.isLoading {
                VideoDetailPgcEpisodeLoadingSection()
            } else if case .failed(let message) = state {
                VideoDetailPgcEpisodeFailedSection(message: message) {
                    Task { await load(force: true) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: loadID) {
            await load(force: false)
        }
        .sheet(isPresented: $isEpisodeSheetPresented) {
            if let season {
                VideoDetailPgcEpisodeSelectionSheet(
                    detail: detail,
                    season: season,
                    selectEpisode: selectEpisode,
                    order: $order
                )
            }
        }
    }

    private func load(force: Bool) async {
        guard force || season == nil else { return }
        let epID = resolvedEpisodeID
        guard detail.pgcSeasonID != nil || epID != nil else {
            state = .failed("暂无分集信息")
            return
        }
        state = .loading
        do {
            season = try await dependencies.api.fetchPgcSeasonInfo(
                seasonID: detail.pgcSeasonID,
                epID: epID
            )
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct VideoDetailPgcEpisodeLoadedSection: View {
    let detail: VideoItem
    let season: PgcSeasonInfo
    let selectEpisode: (VideoItem) -> Void
    @Binding var order: VideoDetailPgcEpisodeOrder
    @Binding var showsEpisodeSheet: Bool

    private var orderedEpisodes: [PgcEpisode] {
        order.episodes(from: season.selectableEpisodes)
    }

    var body: some View {
        if !orderedEpisodes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                VideoDetailPgcEpisodeHeader(
                    episodeCount: season.selectableEpisodes.count,
                    order: $order,
                    showsEpisodeSheet: $showsEpisodeSheet
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(orderedEpisodes) { episode in
                            VideoDetailPgcEpisodeRoute(
                                episode: episode,
                                season: season,
                                selectEpisode: selectEpisode,
                                isSelected: episode.matches(detail: detail),
                                width: 124,
                                height: 54
                            )
                        }
                    }
                }
                .padding(.horizontal, -16)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .frame(height: 54)
            }
        }
    }
}

private struct VideoDetailPgcEpisodeHeader: View {
    let episodeCount: Int
    @Binding var order: VideoDetailPgcEpisodeOrder
    @Binding var showsEpisodeSheet: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("分集")
                .font(.headline)

            if episodeCount > 0 {
                Text("\(episodeCount) 集")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                order.toggle()
            } label: {
                Label(order.title, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                showsEpisodeSheet = true
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(180))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("展开全部分集")
        }
    }
}

private struct VideoDetailPgcEpisodeRoute: View {
    let episode: PgcEpisode
    let season: PgcSeasonInfo
    let selectEpisode: (VideoItem) -> Void
    let isSelected: Bool
    let width: CGFloat?
    let height: CGFloat

    var body: some View {
        if let video = episode.videoItem(in: season), !isSelected {
            Button {
                selectEpisode(video)
            } label: {
                VideoDetailPgcEpisodeTile(
                    episode: episode,
                    isSelected: isSelected,
                    isPlayable: true,
                    width: width,
                    height: height
                )
            }
            .buttonStyle(.plain)
        } else {
            VideoDetailPgcEpisodeTile(
                episode: episode,
                isSelected: isSelected,
                isPlayable: episode.videoItem(in: season) != nil,
                width: width,
                height: height
            )
        }
    }
}

private struct VideoDetailPgcEpisodeSheetRoute: View {
    let episode: PgcEpisode
    let season: PgcSeasonInfo
    let selectEpisode: (VideoItem) -> Void
    let isSelected: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.prewarmVideoRouteAction) private var prewarmVideoRoute

    var body: some View {
        if isSelected {
            Button {
                dismiss()
            } label: {
                VideoDetailPgcEpisodeTile(
                    episode: episode,
                    isSelected: true,
                    isPlayable: true,
                    width: nil,
                    height: 68,
                    usesGlassBackground: true
                )
            }
            .buttonStyle(.plain)
        } else if let video = episode.videoItem(in: season) {
            Button {
                prewarmVideoRoute?(video)
                dismiss()
                selectEpisode(video)
            } label: {
                VideoDetailPgcEpisodeTile(
                    episode: episode,
                    isSelected: isSelected,
                    isPlayable: true,
                    width: nil,
                    height: 68,
                    usesGlassBackground: true
                )
            }
            .buttonStyle(.plain)
        } else {
            VideoDetailPgcEpisodeTile(
                episode: episode,
                isSelected: isSelected,
                isPlayable: false,
                width: nil,
                height: 68,
                usesGlassBackground: true
            )
        }
    }
}

private struct VideoDetailPgcEpisodeTile: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let episode: PgcEpisode
    let isSelected: Bool
    let isPlayable: Bool
    let width: CGFloat?
    let height: CGFloat
    let usesGlassBackground: Bool

    init(
        episode: PgcEpisode,
        isSelected: Bool,
        isPlayable: Bool,
        width: CGFloat? = nil,
        height: CGFloat = 56,
        usesGlassBackground: Bool = false
    ) {
        self.episode = episode
        self.isSelected = isSelected
        self.isPlayable = isPlayable
        self.width = width
        self.height = height
        self.usesGlassBackground = usesGlassBackground
    }

    var body: some View {
        selectionSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(episode.displayTitle)
                        .font(titleFont)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if usesGlassBackground, isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(appTintColor)
                            .accessibilityHidden(true)
                    }
                }

                HStack(spacing: 8) {
                    if let badge = episode.badge?.trimmedNonEmpty {
                        SearchSoftPill(badge)
                    }
                    if let duration = episode.durationSeconds {
                        Text(BiliFormatters.duration(duration))
                    }
                }
                .font(metadataFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isPlayable ? 1 : 0.55)
        .accessibilityLabel(episode.displayTitle)
        .accessibilityValue(isSelected ? "当前播放" : "")
    }

    @ViewBuilder
    private func selectionSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if usesGlassBackground {
            content()
                .background(glassFill, in: shape)
                .commentPlayerGlassRoundedRectangle(cornerRadius: 12, showsShadow: false)
                .overlay {
                    shape.strokeBorder(borderColor, lineWidth: borderWidth)
                }
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        } else {
            content()
                .background(Color(.secondarySystemGroupedBackground), in: shape)
                .overlay {
                    shape.strokeBorder(borderColor, lineWidth: borderWidth)
                }
        }
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.4 : 0.8
    }

    private var glassFill: Color {
        if isSelected {
            return appTintColor.opacity(0.14)
        }
        return Color(.systemBackground).opacity(0.58)
    }

    private var borderColor: Color {
        if isSelected {
            return appTintColor
        }
        return usesGlassBackground ? Color.primary.opacity(0.16) : Color(.separator).opacity(0.16)
    }

    private var titleFont: Font {
        usesGlassBackground ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var metadataFont: Font {
        usesGlassBackground ? .caption.weight(.medium) : .caption
    }

    private var horizontalPadding: CGFloat {
        usesGlassBackground ? 14 : 12
    }

    private var verticalPadding: CGFloat {
        usesGlassBackground ? 10 : 8
    }
}

private struct VideoDetailPgcEpisodeSelectionSheet: View {
    let detail: VideoItem
    let season: PgcSeasonInfo
    let selectEpisode: (VideoItem) -> Void
    @Binding var order: VideoDetailPgcEpisodeOrder

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var orderedEpisodes: [PgcEpisode] {
        order.episodes(from: season.selectableEpisodes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VideoDetailPgcEpisodeSheetHeader(
                        episodeCount: season.selectableEpisodes.count,
                        order: $order
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                    GlassEffectContainer(spacing: 10) {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(orderedEpisodes) { episode in
                                VideoDetailPgcEpisodeSheetRoute(
                                    episode: episode,
                                    season: season,
                                    selectEpisode: selectEpisode,
                                    isSelected: episode.matches(detail: detail)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .scrollContentBackground(.hidden)
            .background(.clear)
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }
}

private struct VideoDetailPgcEpisodeSheetHeader: View {
    let episodeCount: Int
    @Binding var order: VideoDetailPgcEpisodeOrder

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 10) {
                Text("全部分集")
                    .font(.headline)

                Text("\(episodeCount) 集")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    order.toggle()
                } label: {
                    Label(order.title, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .commentPlayerGlassCapsule(showsShadow: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .commentPlayerGlassRoundedRectangle(cornerRadius: 14, showsShadow: false)
        }
    }
}

private struct VideoDetailPgcEpisodeLoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分集")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                SkeletonBlock(width: 54, height: 13, shape: .capsule)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonBlock(width: 118, height: 56, shape: .rounded(12))
                    }
                }
            }
            .scrollDisabled(true)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("正在加载分集")
    }
}

private struct VideoDetailPgcEpisodeFailedSection: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("分集")
                    .font(.headline)
                Spacer()
                Button("重试", action: retry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(appTintColor)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private enum VideoDetailPgcEpisodeOrder {
    case ascending
    case descending

    var title: String {
        switch self {
        case .ascending:
            return "正序"
        case .descending:
            return "倒序"
        }
    }

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }

    func episodes(from episodes: [PgcEpisode]) -> [PgcEpisode] {
        switch self {
        case .ascending:
            return episodes
        case .descending:
            return Array(episodes.reversed())
        }
    }
}

private extension PgcEpisode {
    func matches(detail: VideoItem) -> Bool {
        if let episodeID = detail.pgcEpisodeID ?? detail.bvid.pgcRouteEpisodeID,
           epID == episodeID || idValue == episodeID {
            return true
        }
        if let cid = detail.cid, self.cid == cid {
            return true
        }
        if let bvid = bvid?.trimmedNonEmpty, bvid == detail.bvid {
            return true
        }
        return false
    }
}

private extension String {
    var pgcRouteEpisodeID: Int? {
        guard hasPrefix("ep") else { return nil }
        return Int(dropFirst(2))
    }

    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
