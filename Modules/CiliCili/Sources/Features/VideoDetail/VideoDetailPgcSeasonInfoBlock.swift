import SwiftUI

struct VideoDetailPgcSeasonInfoBlock: View {
    let season: PgcSeasonInfo
    let detail: VideoItem

    @Environment(\.appThemeTintColor) private var appTintColor
    @State private var isDescriptionExpanded = false

    private var episodeCount: Int {
        season.selectableEpisodes.count
    }

    private var descriptionText: String? {
        normalizedText(season.evaluate)
    }

    private var subtitleText: String? {
        normalizedText(season.subtitle)
    }

    private var needsDescriptionExpansion: Bool {
        guard let descriptionText else { return false }
        return descriptionText.count > 88 || descriptionText.contains("\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PgcSeasonInfoCover(coverURLString: season.normalizedCover)

                VStack(alignment: .leading, spacing: 7) {
                    Text(season.displayTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let score = season.rating?.displayScore {
                            Label("评分 \(score)", systemImage: "star.fill")
                                .foregroundStyle(.orange)
                        }

                        if episodeCount > 0 {
                            Text("共 \(episodeCount) 集")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                    if let subtitleText {
                        Text(subtitleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let descriptionText {
                VStack(alignment: .leading, spacing: 6) {
                    Text(descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(isDescriptionExpanded ? nil : 3)
                        .textSelection(.enabled)

                    if needsDescriptionExpansion {
                        Button(isDescriptionExpanded ? "收起简介" : "展开简介") {
                            withAnimation(.snappy(duration: 0.22)) {
                                isDescriptionExpanded.toggle()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appTintColor)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("番剧 \(season.displayTitle)")
    }

    private func normalizedText(_ text: String?) -> String? {
        let value = (text ?? "")
            .removingHTMLTags()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct PgcSeasonInfoCover: View {
    let coverURLString: String?

    var body: some View {
        CachedRemoteImage(
            url: coverURLString.flatMap(URL.init(string:)),
            targetPixelSize: 360,
            animatesAppearance: true
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            BiliMediaPlaceholder(style: .video, iconSize: 24)
        }
        .frame(width: 88, height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
