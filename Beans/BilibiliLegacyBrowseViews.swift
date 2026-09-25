import SwiftUI

struct BilibiliSearchResults: View {
    let keyword: String
    let type: SearchResultType
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @State private var items: [BilibiliFeedVideo] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 180)
            } else if let error, items.isEmpty {
                ErrorStateView(message: error) { Task { await load() } }
            } else if items.isEmpty {
                EmptyStateView(icon: "magnifyingglass", text: "没有找到相关视频")
            } else {
                BilibiliVideoRows(items: items)
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            // The legacy search screen keeps the video result layout for every
            // Bilibili search tab; the result type still controls the visible tab.
            _ = type
            items = try await BilibiliAPI.shared.videoSearch(keyword, page: 1).items
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BilibiliLiveList: View {
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @State private var rooms: [BilibiliLiveRoom] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let error {
                    ErrorStateView(message: error) { Task { await load() } }
                } else if rooms.isEmpty {
                    ProgressView().frame(minHeight: 180)
                } else {
                    ForEach(rooms) { room in
                        roomRow(room)
                    }
                }
            }
            .padding(16)
        }
        .task { await load() }
    }

    private func roomRow(_ room: BilibiliLiveRoom) -> some View {
        Button {
            navigation.push(.live(room))
        } label: {
            HStack(spacing: 12) {
                CoverImage(url: room.cover, size: 108, aspectRatio: 16 / 9, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 6) {
                    Text(room.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text(room.owner.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(room.viewers)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func load() async {
        do {
            rooms = try await BilibiliAPI.shared.liveRooms(page: 1).items
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BilibiliVideoRows: View {
    let items: [BilibiliFeedVideo]
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @AppStorage(BilibiliExperience.key) private var mode = BilibiliExperience.listen.rawValue

    var body: some View {
        LazyVStack(spacing: 14) {
            ForEach(items) { item in
                Button {
                    if mode == BilibiliExperience.video.rawValue {
                        navigation.push(.video(item.song))
                    } else {
                        let songs = items.map(\.song)
                        player.play(songs: songs, startAt: items.firstIndex(where: { $0.id == item.id }) ?? 0)
                    }
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: item.song.coverURL, size: 130, aspectRatio: 16 / 9, cornerRadius: 9)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.song.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Text(item.song.artists)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(item.song.formattedDuration)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
