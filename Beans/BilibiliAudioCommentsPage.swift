import SwiftUI
import CiliCiliKit

struct BilibiliAudioCommentsPage: View {
    let song: Song
    var body: some View {
        CiliCiliAudioCommentsHost(bvid: (song.bilibiliID ?? "").split(separator: ":").first.map(String.init) ?? "")
    }
}
