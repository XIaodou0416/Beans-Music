import SwiftUI

// MARK: - 评论日期

private let beansCommentDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
}()

func beansCommentDate(_ date: Date) -> String {
    beansCommentDateFormatter.string(from: date)
}

private func beansCommentCountText(songName: String, platform: String? = nil, count: Int) -> String {
    if let platform {
        return String(format: NSLocalizedString("《%@》 · %@ %d 条评论", comment: ""), songName, NSLocalizedString(platform, comment: ""), count)
    }
    return String(format: NSLocalizedString("《%@》 · 共 %d 条评论", comment: ""), songName, count)
}

// MARK: - 评论区

enum CommentsSheetPresentation: Equatable {
    case standard
    case reference
}

struct CommentsSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    let song: Song
    var isExpanded: Bool
    var presentation: CommentsSheetPresentation

    @State private var page: NetEaseAPI.SongCommentPage?
    @State private var qqHotComments: [SongComment] = []
    @State private var qqLatestComments: [SongComment] = []
    @State private var qqTotal = 0
    @State private var qqPageNum = 0
    @State private var kugouHotComments: [SongComment] = []
    @State private var kugouLatestComments: [SongComment] = []
    @State private var kugouTotal = 0
    @State private var kugouPageNum = 1
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var offset = 0
    @State private var selectedSection: CommentSection

    private var limit: Int { song.source == .bilibili ? 20 : 30 }
    @State private var lastBilibiliPageCount = 0
    @State private var loadingNextPage = false
    @State private var officialComments: BilibiliOfficialPage?
    /// QQ 音乐每页条数（接口单页上限 25）
    private let qqPageSize = 25

    init(
        song: Song,
        isExpanded: Bool = false,
        presentation: CommentsSheetPresentation = .standard
    ) {
        self.song = song
        self.isExpanded = isExpanded
        self.presentation = presentation
        _selectedSection = State(initialValue: presentation == .reference ? .hot : .latest)
    }

    private enum CommentSection: String, CaseIterable, Identifiable {
        case hot
        case latest

        var id: String { rawValue }
        var title: String { self == .hot ? "热门评论" : "最新评论" }
    }

    var body: some View {
        Group {
            if presentation == .reference {
                referenceCommentsView
            } else {
                standardCommentsView
            }
        }
        .task { await load(reset: true) }
        .sheet(item: $officialComments) { page in BilibiliOfficialBrowser(page: page) }
    }

    private var standardCommentsView: some View {
        let _ = theme.accent
        return ZStack {
            commentsBackground
            BeansNavigationStack {
                commentsContent
                    .navigationTitle("评论")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if song.source == .bilibili {
                                Button("官方评论") { officialComments = BilibiliOfficialPage.video(song) }
                            }
                        }
                    }
            }
        }
    }

    private var referenceCommentsView: some View {
        BeansNavigationStack {
            Group {
                if loading {
                    ProgressView("正在加载评论")
                } else if let errorMessage {
                    VStack(spacing: 14) {
                        referenceEmptyState(
                            title: "评论加载失败",
                            detail: errorMessage,
                            icon: "wifi.exclamationmark"
                        )
                        Button("重新加载") {
                            Task { await load(reset: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if selectedComments.isEmpty {
                    referenceEmptyState(title: "暂无评论", detail: nil, icon: "text.bubble")
                } else {
                    VStack(spacing: 0) {
                        Picker("评论排序", selection: $selectedSection) {
                            ForEach(CommentSection.allCases) { section in
                                Text(section.title).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        List {
                            ForEach(selectedComments) { comment in
                                ReferenceCommentRow(comment: comment)
                            }
                            if selectedSection == .latest && canLoadMore {
                                Button("加载更多") {
                                    Task { await loadNextPage() }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if song.source == .bilibili {
                        Button("官方评论") { officialComments = BilibiliOfficialPage.video(song) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var commentsContent: some View {
        if loading {
            LoadingStateView()
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) {
                Task { await load(reset: true) }
            }
        } else if song.source == .kugou {
            kugouCommentList
        } else if song.source == .qq {
            qqCommentList
        } else if song.source == .kuwo || song.source == .migu {
            EmptyStateView(icon: "bubble.left", text: "当前平台暂未提供评论")
        } else if let page {
            if page.hot.isEmpty && page.comments.isEmpty {
                EmptyStateView(icon: "bubble.left", text: "暂无评论")
            } else {
                neteaseCommentList(page)
            }
        }
    }

    private var selectedComments: [SongComment] {
        switch song.source {
        case .netease:
            guard let page else { return [] }
            return selectedSection == .hot ? page.hot : page.comments
        case .qq:
            return selectedSection == .hot ? qqHotComments : qqLatestComments
        case .kugou:
            return selectedSection == .hot ? kugouHotComments : kugouLatestComments
        case .kuwo, .migu:
            return []
        case .qishui, .bilibili:
            guard let page else { return [] }
            return selectedSection == .hot ? page.hot : page.comments
        }
    }

    private var canLoadMore: Bool {
        switch song.source {
        case .netease:
            return (page?.comments.count ?? 0) >= limit
        case .qq:
            return qqTotal <= 0 || qqLatestComments.count < qqTotal
        case .kugou:
            return kugouTotal <= 0 || kugouLatestComments.count < kugouTotal
        case .kuwo, .migu:
            return false
        case .qishui:
            return (page?.comments.count ?? 0) >= limit
        case .bilibili:
            return lastBilibiliPageCount >= limit && (page?.total ?? 0) > (page?.comments.count ?? 0)
        }
    }

    private func loadNextPage() async {
        switch song.source {
        case .netease:
            await loadMore()
        case .qq:
            await loadQQMore()
        case .kugou:
            kugouPageNum += 1
            await load(reset: false)
        case .kuwo, .migu:
            return
        case .qishui, .bilibili:
            await loadMore()
        }
    }

    private func referenceEmptyState(title: String, detail: String?, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    @ViewBuilder
    private var commentsBackground: some View {
        if #available(iOS 26, *), !isExpanded {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                BeansGlass(shape: Rectangle(), forceLiquid: true)
            }
            .ignoresSafeArea()
        } else if isExpanded {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
        } else {
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
        }
    }

    private func neteaseCommentList(_ page: NetEaseAPI.SongCommentPage) -> some View {
        List {
            Section {
                Text(beansCommentCountText(songName: song.name, count: page.total))
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }
            .listRowBackground(Color.clear)
            Section {
                Picker("评论分类", selection: $selectedSection) {
                    ForEach(CommentSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section(selectedSection.title) {
                let comments = selectedSection == .hot ? page.hot : page.comments
                if comments.isEmpty {
                    Text("暂无\(selectedSection.title)")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansComment)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            if selectedSection == .latest && canLoadMore {
                Section {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Text("加载更多")
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansAmber)
                            .frame(maxWidth: .infinity)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .beansScrollContentBackgroundHidden()
    }

    private func load(reset: Bool) async {
        if reset {
            lastBilibiliPageCount = 0
            offset = 0
            page = nil
            qqHotComments = []
            qqLatestComments = []
            qqTotal = 0
            qqPageNum = 0
            kugouHotComments = []
            kugouLatestComments = []
            kugouTotal = 0
            kugouPageNum = 1
            loading = true
        }
        guard song.source != .kuwo, song.source != .migu else {
            loading = false
            return
        }
        errorMessage = nil
        do {
            if song.source == .kugou {
                let mixSongID = song.kugouAlbumAudioId ?? ""
                let result = try await KugouMusicAPI.shared.comments(
                    mixSongID: mixSongID,
                    hash: song.kugouHash,
                    page: kugouPageNum,
                    limit: limit
                )
                if reset {
                    kugouHotComments = result.hotComments
                    kugouLatestComments = result.comments
                } else {
                    kugouLatestComments.append(contentsOf: result.comments)
                }
                kugouTotal = result.total
                loading = false
                return
            } else if song.source == .qq {
                let result = try await QQMusicAPI.shared.comments(songID: song.id, limit: qqPageSize, pagenum: qqPageNum)
                if reset {
                    qqHotComments = result.hotComments
                    qqLatestComments = result.comments
                } else {
                    qqLatestComments.append(contentsOf: result.comments)
                }
                qqTotal = result.total
            } else if song.source == .qishui {
                let result = try await QishuiAPI.shared.comments(for: song, limit: limit)
                if reset {
                    page = result
                } else if var current = page {
                    current.comments.append(contentsOf: result.comments)
                    page = current
                }
            } else if song.source == .bilibili {
                let result = try await BilibiliAPI.shared.comments(for: song, limit: limit, offset: offset)
                lastBilibiliPageCount = result.comments.count
                if reset {
                    page = result
                } else if var current = page {
                    let existing = Set(current.comments.map(\.id))
                    current.comments.append(contentsOf: result.comments.filter { !existing.contains($0.id) })
                    page = current
                }
            } else {
                let result = try await NetEaseAPI.shared.songComments(id: song.id, limit: limit, offset: offset)
                if reset {
                    page = result
                } else if var current = page {
                    current.comments.append(contentsOf: result.comments)
                    page = current
                }
            }
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }

    /// QQ 音乐评论列表（分页加载更多）
    private var qqCommentList: some View {
        Group {
            if qqHotComments.isEmpty && qqLatestComments.isEmpty {
                EmptyStateView(icon: "bubble.left", text: "暂无评论")
            } else {
                List {
                    Section {
                        Text(beansCommentCountText(songName: song.name, platform: "QQ 音乐", count: qqTotal > 0 ? qqTotal : qqLatestComments.count))
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                    }
                    .listRowBackground(Color.clear)
                    Section {
                        Picker("评论分类", selection: $selectedSection) {
                            ForEach(CommentSection.allCases) { section in
                                Text(section.title).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                    Section(selectedSection.title) {
                        let comments = selectedSection == .hot ? qqHotComments : qqLatestComments
                        if comments.isEmpty {
                            emptyCommentSection
                        } else {
                            ForEach(comments) { comment in
                                CommentRow(comment: comment)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                    if selectedSection == .latest && (qqTotal <= 0 || qqLatestComments.count < qqTotal) {
                        Section {
                            Button {
                                Task { await loadQQMore() }
                            } label: {
                                Text("加载更多")
                                    .font(BeansFont.appFont(14, .semibold))
                                    .foregroundStyle(Color.beansAmber)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .beansScrollContentBackgroundHidden()
            }
        }
    }

    /// QQ 评论翻页
    private func loadQQMore() async {
        qqPageNum += 1
        await load(reset: false)
    }

    private var kugouCommentList: some View {
        Group {
            if kugouHotComments.isEmpty && kugouLatestComments.isEmpty {
                EmptyStateView(icon: "bubble.left", text: "暂无评论")
            } else {
                List {
                    Section {
                        Text(beansCommentCountText(songName: song.name, platform: "酷狗音乐", count: kugouTotal > 0 ? kugouTotal : kugouLatestComments.count + kugouHotComments.count))
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                    }
                    .listRowBackground(Color.clear)
                    Section {
                        Picker("评论分类", selection: $selectedSection) {
                            ForEach(CommentSection.allCases) { section in
                                Text(section.title).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                    Section(selectedSection.title) {
                        let comments = selectedSection == .hot ? kugouHotComments : kugouLatestComments
                        if comments.isEmpty {
                            emptyCommentSection
                        } else {
                            ForEach(comments) { comment in
                                CommentRow(comment: comment)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                    if selectedSection == .latest && (kugouTotal <= 0 || kugouLatestComments.count < kugouTotal) {
                        Section {
                            Button {
                                kugouPageNum += 1
                                Task { await load(reset: false) }
                            } label: {
                                Text("加载更多")
                                    .font(BeansFont.appFont(14, .semibold))
                                    .foregroundStyle(Color.beansAmber)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .beansScrollContentBackgroundHidden()
            }
        }
    }

    private func loadMore() async {
        guard !loadingNextPage else { return }
        loadingNextPage = true
        defer { loadingNextPage = false }
        let previousOffset = offset
        offset += limit
        await load(reset: false)
        if errorMessage != nil { offset = previousOffset }
    }

    private var emptyCommentSection: some View {
        Text("暂无\(selectedSection.title)")
            .font(BeansFont.appFont(13))
            .foregroundStyle(Color.beansComment)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
    }
}

/// 评论区使用独立宿主保存当前半屏/全屏状态，避免把 detent 状态藏在内容视图外
/// 导致展开后背景仍然保持液态效果。
struct CommentsSheetHost: View {
    let song: Song
    var presentation: CommentsSheetPresentation = .standard

    var body: some View {
        if #available(iOS 16, *) {
            CommentsSheetDetentHost(song: song, presentation: presentation)
        } else {
            CommentsSheet(song: song, presentation: presentation)
        }
    }
}

@available(iOS 16, *)
private struct CommentsSheetDetentHost: View {
    let song: Song
    let presentation: CommentsSheetPresentation
    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        let content = CommentsSheet(
            song: song,
            isExpanded: selectedDetent == .large,
            presentation: presentation
        )
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationDragIndicator(.visible)

        if presentation == .standard {
            if #available(iOS 16.4, *) {
                content
                    .presentationBackground(.clear)
                    .presentationCornerRadius(28)
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct ReferenceCommentRow: View {
    let comment: SongComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(comment.nickname)
                    .font(BeansFont.appFont(15, .medium))
                    .lineLimit(1)
                Text(beansCommentDate(comment.time))
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("赞 \(comment.likedCount)")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(.secondary)
            }

            Text(comment.content)
                .font(BeansFont.appFont(15))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 评论行

struct CommentRow: View {
    @EnvironmentObject private var theme: ThemeStore
    let comment: SongComment

    var body: some View {
        let _ = theme.accent
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: comment.avatarURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.beansComment)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .background(Color.beansGlassFill, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(comment.nickname)
                        .font(BeansFont.appFont(13, .medium))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                    if comment.isHot {
                        Text("热评")
                            .font(BeansFont.appFont(9, .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(LinearGradient.beansAccent, in: Capsule())
                    }
                    Spacer()
                    Text(beansCommentDate(comment.time))
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment.opacity(0.8))
                }
                Text(comment.content)
                    .font(BeansFont.appFont(14))
                    .foregroundStyle(Color.beansLabel)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Label("\(comment.likedCount)", systemImage: "heart")
                        .font(BeansFont.appFont(11, .medium))
                        .foregroundStyle(Color.beansComment)
                        .labelStyle(.trailingIcon)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

// 图标在文字后面
extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
