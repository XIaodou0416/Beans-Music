import Foundation

extension RootTabView {
    static var initialTab: RootTab {
        if argumentValue(after: "--start-live-room") != nil {
            return .live
        }
        if let value = argumentValue(after: "--start-tab"),
           let tab = RootTab(argumentValue: value) {
            return tab
        }
        return .home
    }

    nonisolated static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        let value = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated static func argumentInt(after flag: String) -> Int? {
        argumentValue(after: flag).flatMap(Int.init)
    }

    nonisolated static func seedVideo(bvid: String) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: nil,
            title: "正在加载",
            pic: nil,
            desc: nil,
            duration: nil,
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    nonisolated static func seedLiveRoom(roomID: Int) -> LiveRoom {
        LiveRoom(
            roomID: roomID,
            title: "正在进入直播间",
            uname: "直播间",
            uid: nil,
            face: nil,
            cover: nil,
            keyframe: nil,
            online: nil,
            areaName: nil,
            parentAreaName: nil,
            liveStatus: 1
        )
    }

    nonisolated static func seedUploader(mid: Int) -> VideoOwner {
        VideoOwner(mid: mid, name: "用户主页", face: nil)
    }
}
