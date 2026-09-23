import SwiftUI

struct BilibiliNativeSheet: View {
    let route: BilibiliNativeRoute
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        BeansNavigationStack {
            destination
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
        }
    }
    private var destination: AnyView {
        switch route {
        case .video(let song): return AnyView(BilibiliVideoPage(song: song))
        case .up(let owner): return AnyView(BilibiliUPPage(owner: owner))
        case .collection(let collection): return AnyView(BilibiliCollectionPage(collection: collection))
        case .live(let room): return AnyView(BilibiliLivePage(room: room))
        }
    }
}

struct BilibiliVideoRows: View {
    let items: [BilibiliFeedVideo]
    var onAppearItem: (String) -> Void = { _ in }
    @EnvironmentObject private var player: PlayerManager
    @AppStorage(BilibiliExperience.key) private var mode = BilibiliExperience.listen.rawValue
    @State private var route: BilibiliNativeRoute?
    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(items) { item in
                Button {
                    if mode == BilibiliExperience.video.rawValue { route = .video(item.song) }
                    else { player.play(songs: items.map(\.song), startAt: items.firstIndex(where: { $0.id == item.id }) ?? 0) }
                } label: { BilibiliVideoRow(item: item) }
                .buttonStyle(.plain)
                .onAppear { onAppearItem(item.id) }
                .contextMenu {
                    Button { route = .video(item.song) } label: { Label("视频详情", systemImage: "play.rectangle") }
                    Button { player.playNext(item.song) } label: { Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") }
                }
            }
        }
        .sheet(item: $route) { BilibiliNativeSheet(route: $0) }
    }
}

struct BilibiliVideoRow: View {
    let item: BilibiliFeedVideo
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: item.song.coverURL, size: 68, aspectRatio: 16.0 / 9.0, cornerRadius: 9)
                .overlay(alignment: .bottomTrailing) {
                    Text(item.song.formattedDuration).font(.caption2).monospacedDigit()
                        .foregroundStyle(.white).padding(4).background(.black.opacity(0.65)).cornerRadius(4).padding(4)
                }
            VStack(alignment: .leading, spacing: 7) {
                Text(item.song.name).font(BeansFont.appFont(14, .medium)).foregroundStyle(Color.beansLabel).lineLimit(2)
                Text(item.song.artists).font(BeansFont.appFont(11)).foregroundStyle(Color.beansComment).lineLimit(1)
                if item.playCount > 0 {
                    Label(BilibiliFeedVideo.countLabel(item.playCount), systemImage: "play.rectangle")
                        .font(.caption2).foregroundStyle(Color.beansComment)
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

struct BilibiliCollectionRow: View {
    let collection: BilibiliSeries
    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: collection.cover, size: 66, aspectRatio: 1.3, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 6) {
                Text(collection.title).font(BeansFont.appFont(15, .semibold)).foregroundStyle(Color.beansLabel).lineLimit(2)
                Text("\(collection.ownerName) · \(collection.count) 个视频").font(.caption).foregroundStyle(Color.beansComment)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.beansComment)
        }.frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).contentShape(Rectangle())
    }
}

struct BilibiliInlineError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text(message).font(.footnote).foregroundStyle(Color.beansComment).multilineTextAlignment(.center)
            Button("重试", action: retry).frame(minHeight: 44)
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}
