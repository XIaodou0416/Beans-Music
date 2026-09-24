import SwiftUI

struct LiveRoomCard: View {
    let room: LiveRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveRoomCardCover(
                coverURL: coverURL,
                fallbackCoverURL: fallbackCoverURL,
                avatarCoverFallbackURL: avatarCoverFallbackURL
            )
            .videoCardBorderedCover()

            LiveRoomCardMetadataRow(
                room: room,
                title: title,
                anchorName: anchorName,
                metadataText: metadataText
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .videoCardBorderedSurface(cornerRadius: 18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var coverURL: URL? {
        primaryCoverURLString
            .map { $0.biliCoverThumbnailURL(width: 420, height: 236) }
            .flatMap(URL.init(string:))
    }

    private var fallbackCoverURL: URL? {
        fallbackCoverURLString
            .map { $0.biliCoverThumbnailURL(width: 420, height: 236) }
            .flatMap(URL.init(string:))
    }

    private var avatarCoverFallbackURL: URL? {
        guard let face = room.face?.normalizedBiliURL() else { return nil }
        return URL(string: face.biliAvatarThumbnailURL(size: 240))
    }

    private var primaryCoverURLString: String? {
        room.coverCandidates.first
    }

    private var fallbackCoverURLString: String? {
        room.coverCandidates.dropFirst().first
    }

    private var title: String {
        room.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "直播间"
    }

    private var anchorName: String {
        room.uname.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "UP 主"
    }

    private var onlineText: String? {
        guard let online = room.online, online > 0 else { return nil }
        return BiliFormatters.compactCount(online)
    }

    private var areaText: String? {
        [room.parentAreaName, room.areaName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " / ")
            .nilIfEmpty
    }

    private var metadataText: String {
        [areaText, onlineText.map { "\($0)在线" }]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        [title, anchorName, areaText, onlineText.map { "\($0)人在线" }]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}
