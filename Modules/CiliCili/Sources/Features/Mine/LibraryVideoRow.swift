import SwiftUI

struct LibraryVideoRow: View {
    let item: AccountVideoEntry
    let timestampTitle: String

    var body: some View {
        HStack(spacing: 10) {
            LibraryVideoCover(urlString: item.pic?.normalizedBiliURL())
            LibraryVideoInfo(item: item, timestampTitle: timestampTitle)
        }
        .padding(.vertical, 3)
    }
}

private struct LibraryVideoCover: View {
    let urlString: String?

    var body: some View {
        CachedRemoteImage(
            url: urlString.flatMap { URL(string: $0.biliCoverThumbnailURL(width: 288, height: 180)) },
            fallbackURL: urlString.flatMap(URL.init(string:)),
            targetPixelSize: 288
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.gray.opacity(0.14)
        }
        .frame(width: 92, height: 58)
        .videoCoverSurface(cornerRadius: 8, shadowLevel: .subtle)
    }
}

private struct LibraryVideoInfo: View {
    let item: AccountVideoEntry
    let timestampTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if let ownerName = item.owner?.name, !ownerName.isEmpty {
                Text(ownerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(BiliFormatters.compactCount(item.stat?.view), systemImage: "play.rectangle")
                Text("\(timestampTitle) \(item.savedAt.formatted(date: .numeric, time: .shortened))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let resumeTime = item.resumeTime {
                LibraryVideoProgress(resumeTime: resumeTime, progress: item.playbackProgress)
            }
        }
    }
}

private struct LibraryVideoProgress: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let resumeTime: Double
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("看到 \(BiliFormatters.duration(Int(resumeTime)))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTintColor)

            if let progress {
                ProgressView(value: progress)
                    .tint(appTintColor)
            }
        }
    }
}
