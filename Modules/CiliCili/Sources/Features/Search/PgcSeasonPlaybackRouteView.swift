import SwiftUI

struct PgcSeasonPlaybackRouteView: View {
    let route: PgcSeasonRoute
    let onRequestClose: (() -> Void)?
    let onPopOne: (() -> Void)?

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var selectedVideo: VideoItem?
    @State private var state: LoadingState = .idle

    init(
        route: PgcSeasonRoute,
        onRequestClose: (() -> Void)? = nil,
        onPopOne: (() -> Void)? = nil
    ) {
        self.route = route
        self.onRequestClose = onRequestClose
        self.onPopOne = onPopOne
    }

    var body: some View {
        Group {
            if let selectedVideo {
                VideoDetailView(
                    seedVideo: selectedVideo,
                    onRequestClose: onRequestClose,
                    onPopOne: onPopOne
                )
                .id(selectedVideo.id)
            } else {
                PgcSeasonPlaybackRouteLoadingView(
                    route: route,
                    state: state,
                    retry: reload
                )
            }
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: route.id) {
            await load()
        }
    }

    private func reload() {
        Task { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        guard force || selectedVideo == nil else { return }

        state = .loading
        do {
            let season = try await dependencies.api.fetchPgcSeasonInfo(seasonID: route.seasonID)
                .withFallbackSeasonID(route.seasonID)
            guard !Task.isCancelled else { return }
            guard let episode = season.preferredPlaybackEpisode,
                  let video = episode.videoItem(in: season) else {
                state = .failed("暂无可播放分集")
                return
            }

            selectedVideo = video
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct PgcSeasonPlaybackRouteLoadingView: View {
    let route: PgcSeasonRoute
    let state: LoadingState
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if case .failed(let message) = state {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                Text(route.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityLabel("正在打开番剧")
    }
}
