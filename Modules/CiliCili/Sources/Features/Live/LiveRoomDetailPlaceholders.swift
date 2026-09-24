import SwiftUI

struct LiveRoomInitialPlaceholder: View {
    let room: LiveRoom

    var body: some View {
        VStack(spacing: 12) {
            LivePlayerLoadingPlaceholder(
                title: room.title.nilIfEmpty ?? "正在进入直播间",
                subtitle: room.uname.nilIfEmpty ?? "准备直播信息"
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .mediaShadow(.control)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
        .background(VideoDetailTheme.background)
    }
}
