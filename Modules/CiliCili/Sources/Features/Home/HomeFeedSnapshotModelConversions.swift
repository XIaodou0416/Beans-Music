import Foundation

extension HomeFeedCachedVideo {
    nonisolated init(video: VideoItem) {
        bvid = video.bvid
        aid = video.aid
        title = video.title
        pic = video.pic
        desc = video.desc
        duration = video.duration
        pubdate = video.pubdate
        owner = video.owner.map(HomeFeedCachedOwner.init(owner:))
        stat = video.stat.map(HomeFeedCachedStat.init(stat:))
        cid = video.cid
        recommendReason = video.recommendReason
    }

    @MainActor var videoItem: VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic,
            desc: desc,
            duration: duration,
            pubdate: pubdate,
            owner: owner?.videoOwner,
            stat: stat?.videoStat,
            cid: cid,
            pages: nil,
            dimension: nil,
            recommendReason: recommendReason
        )
    }
}
