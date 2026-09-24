import Foundation

extension HomeFeedCachedStat {
    nonisolated init(stat: VideoStat) {
        view = stat.view
        reply = stat.reply
        like = stat.like
        coin = stat.coin
        favorite = stat.favorite
    }

    nonisolated var videoStat: VideoStat {
        VideoStat(
            view: view,
            reply: reply,
            like: like,
            coin: coin,
            favorite: favorite
        )
    }
}
