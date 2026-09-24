import Foundation

@MainActor
extension LiveRoomViewModel {
    var roomID: Int {
        roomInfo?.roomID ?? roomSummary?.roomID ?? seedRoom.roomID
    }

    var title: String {
        let value = roomInfo?.title ?? roomSummary?.title ?? seedRoom.title
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "直播间" : value
    }

    var coverURL: String? {
        (roomInfo?.displayCover ?? roomSummary?.cover ?? seedRoom.displayCover)?.normalizedBiliURL()
    }

    var areaText: String? {
        let parentAreaName: String? = roomInfo?.parentAreaName ?? seedRoom.parentAreaName
        let areaName: String? = roomInfo?.areaName ?? seedRoom.areaName
        return [parentAreaName, areaName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
            .nilIfEmpty
    }

    var onlineText: String {
        let online = roomInfo?.online ?? roomSummary?.online ?? seedRoom.online
        guard let online, online > 0 else { return "在线人数 -" }
        return "在线 \(BiliFormatters.compactCount(online))"
    }

    var onlineActionText: String {
        let online = roomInfo?.online ?? roomSummary?.online ?? seedRoom.online
        guard let online, online > 0 else { return "-" }
        return BiliFormatters.compactCount(online)
    }

    var areaActionText: String {
        roomInfo?.areaName?.nilIfEmpty
            ?? seedRoom.areaName?.nilIfEmpty
            ?? roomInfo?.parentAreaName?.nilIfEmpty
            ?? seedRoom.parentAreaName?.nilIfEmpty
            ?? "分区"
    }

    var liveTimeText: String? {
        roomInfo?.liveTime?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var descriptionText: String? {
        roomInfo?.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var anchorName: String {
        anchorInfo?.info?.uname?.nilIfEmpty ?? seedRoom.uname
    }

    var anchorFace: String? {
        anchorInfo?.info?.face?.normalizedBiliURL() ?? seedRoom.face?.normalizedBiliURL()
    }

    var anchorUIDForFollow: Int? {
        let uid = anchorInfo?.info?.uid ?? roomInfo?.uid ?? seedRoom.uid
        guard let uid, uid > 0 else { return nil }
        return uid
    }

    var anchorOwner: VideoOwner {
        VideoOwner(mid: anchorUIDForFollow ?? 0, name: anchorName, face: anchorFace)
    }

    var isFollowingAnchor: Bool {
        (anchorInfo?.relationInfo?.attention ?? 0) > 0
    }

    var isLive: Bool {
        if let roomInfo {
            return roomInfo.isLive
        }
        if let liveStatus = roomSummary?.liveStatus {
            return liveStatus == 1
        }
        return seedRoom.isLive
    }

    var hasMultipleStreamCandidates: Bool {
        streamMenuItems.count > 1
    }

    var hasMultipleQualities: Bool {
        qualityMenuItems.count > 1
    }

    var effectiveDanmakuSettings: DanmakuSettings {
        var settings = danmakuSettings.normalized
        settings.loadFactor = min(settings.loadFactor, 0.75)
        return settings
    }

}
