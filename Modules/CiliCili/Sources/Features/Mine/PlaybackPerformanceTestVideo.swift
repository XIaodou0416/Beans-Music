import Foundation

struct PlaybackPerformanceTestVideo: Identifiable {
    let bvid: String
    let title: String

    var id: String { bvid }

    var seedVideo: VideoItem {
        VideoItem(
            bvid: bvid,
            aid: nil,
            title: title,
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

    static let fixedSamples = [
        PlaybackPerformanceTestVideo(
            bvid: "BV1RL3F6HErM",
            title: "为什么骁龙是安卓首选？骁龙发展史"
        ),
        PlaybackPerformanceTestVideo(
            bvid: "BV1vd316QEP4",
            title: "李奇：我45°角仰望天空，你TM骗走我十块钱！"
        ),
        PlaybackPerformanceTestVideo(
            bvid: "BV1Aw3o6bE48",
            title: "最癫的外壳，最狠的内核！《年会不能停！2》"
        ),
        PlaybackPerformanceTestVideo(
            bvid: "BV1WwuZ68Ey6",
            title: "中国企业都干到全球第一了，为什么工薪族还在给网贷打工？"
        ),
        PlaybackPerformanceTestVideo(
            bvid: "BV1dsut6wEBn",
            title: "搞笑解说《顶级魅魔罗子君》"
        )
    ]
}
