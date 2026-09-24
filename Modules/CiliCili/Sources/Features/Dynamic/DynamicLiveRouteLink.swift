import SwiftUI

struct DynamicLiveRouteLink<Label: View>: View {
    let room: LiveRoom?
    @ViewBuilder let label: () -> Label
    @Environment(\.openLiveRoomAction) private var openLiveRoom
    @State private var selectedRoom: LiveRoom?

    @ViewBuilder
    var body: some View {
        if let openLiveRoom {
            Button {
                if let room {
                    openLiveRoom(room)
                }
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(room == nil)
            .opacity(room == nil ? 0.72 : 1)
        } else {
            Button {
                selectedRoom = room
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(room == nil)
            .opacity(room == nil ? 0.72 : 1)
            .navigationDestination(item: $selectedRoom) { room in
                LiveRoomDetailView(seedRoom: room)
            }
        }
    }
}
