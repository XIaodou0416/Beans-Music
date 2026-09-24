import SwiftUI

struct DynamicTopUploaderStripItem: Identifiable, Hashable {
    let owner: VideoOwner
    let liveRoom: LiveRoom?

    var id: String {
        if owner.mid > 0 {
            return "up-\(owner.mid)"
        }
        if let liveRoom {
            return "live-\(liveRoom.roomID)"
        }
        return "up-\(owner.name)"
    }

    var isLive: Bool {
        liveRoom != nil
    }
}

struct FollowedLiveStrip: View {
    let items: [DynamicTopUploaderStripItem]
    let isLoading: Bool
    @Environment(\.openLiveRoomAction) private var openLiveRoom

    var body: some View {
        if !items.isEmpty || isLoading {
            VStack(alignment: .leading, spacing: 8) {
                Text("最常访问")
                    .appTypography(
                        .commentAuthor,
                        fallback: .subheadline.weight(.semibold)
                    )
                    .padding(.horizontal, 2)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        if items.isEmpty {
                            ForEach(0..<10, id: \.self) { _ in
                                FollowedLiveAvatarPlaceholder()
                            }
                        } else {
                            ForEach(items) { item in
                                stripItemLink(item)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .padding(.bottom, 10)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private func stripItemLink(_ item: DynamicTopUploaderStripItem) -> some View {
        if let liveRoom = item.liveRoom {
            if let openLiveRoom {
                Button {
                    openLiveRoom(liveRoom)
                } label: {
                    FollowedLiveAvatar(item: item)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: liveRoom) {
                    FollowedLiveAvatar(item: item)
                }
                .buttonStyle(.plain)
            }
        } else if item.owner.mid > 0 {
            VideoOwnerRouteLink(owner: item.owner) {
                FollowedLiveAvatar(item: item)
            }
        } else {
            FollowedLiveAvatar(item: item)
        }
    }
}

private struct FollowedLiveAvatarPlaceholder: View {
    var body: some View {
        VStack(spacing: 5) {
            SkeletonBlock(width: 48, height: 48, shape: .circle)
                .mediaShadow(.regular)

            SkeletonBlock(width: 42, height: 10, shape: .capsule)
        }
        .frame(width: 60)
        .accessibilityHidden(true)
    }
}

private struct FollowedLiveAvatar: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let item: DynamicTopUploaderStripItem

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                AvatarRemoteImage(urlString: item.owner.face, pixelSize: 96) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(appTintColor.opacity(0.72), lineWidth: 1.5)
                }
                .mediaShadow(.regular)

                if item.isLive {
                    Text("直播中")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .videoCoverBadgeBackground(style: .regular, in: Capsule())
                        .offset(y: 4)
                }
            }

            Text(anchorName)
                .appTypography(
                    .compactAuthor,
                    fallback: .caption2.weight(.semibold)
                )
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 58)
        }
        .frame(width: 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.isLive ? "\(anchorName) 正在直播" : anchorName)
    }

    private var anchorName: String {
        let trimmedName = item.owner.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "UP 主" : trimmedName
    }
}
