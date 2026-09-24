import SwiftUI

struct ResourceCacheCleanupSection: View {
    let performClear: (@escaping () async -> Void) -> Void

    var body: some View {
        Section("清理") {
            Button {
                performClear {
                    await ResourceCacheCenter.clearPlayURL()
                }
            } label: {
                MineSettingsLabel("清理播放源缓存", systemImage: "link.badge.minus")
            }

            Button {
                performClear {
                    await ResourceCacheCenter.clearImages(includeDisk: true)
                }
            } label: {
                MineSettingsLabel("清理图片缓存", systemImage: "photo.badge.arrow.down")
            }

            Button {
                performClear {
                    await ResourceCacheCenter.clearAPI()
                }
            } label: {
                MineSettingsLabel("清理 API 缓存", systemImage: "network")
            }

            Button {
                performClear {
                    await ResourceCacheCenter.clearProgressiveMedia()
                }
            } label: {
                MineSettingsLabel("清理播放片段缓存", systemImage: "externaldrive.badge.minus")
            }

            Button {
                performClear {
                    await ResourceCacheCenter.clearSubtitlesAndDanmaku()
                }
            } label: {
                MineSettingsLabel("清理字幕/弹幕缓存", systemImage: "text.bubble")
            }

            Button(role: .destructive) {
                performClear {
                    await ResourceCacheCenter.clearAll()
                }
            } label: {
                MineSettingsLabel("清理全部资源缓存", systemImage: "trash")
            }
        }
    }
}
