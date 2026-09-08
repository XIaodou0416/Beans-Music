import UIKit
import SwiftUI

/// 主页和“我的”共用的自定义头像，图片只保存在本机沙盒内。
@MainActor
final class BeansAvatarStore: ObservableObject {
    static let shared = BeansAvatarStore()

    @Published private(set) var path: String
    private let defaultsKey = "beans.profile.customAvatarPath"

    private init() {
        path = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
    }

    func save(data: Data) {
        let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansProfileAvatar.jpg")
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.88) else { return }
            try jpeg.write(to: fileURL, options: .atomic)
            path = fileURL.path
            UserDefaults.standard.set(path, forKey: defaultsKey)
            BeansImageFileCache.remove(path)
        } catch {
            BeansLogger.shared.log("自定义头像保存失败：\(error.localizedDescription)", level: .warn)
        }
    }

    func clear() {
        if !path.isEmpty {
            try? FileManager.default.removeItem(atPath: path)
            BeansImageFileCache.remove(path)
        }
        path = ""
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

struct BeansAvatarView: View {
    let remoteURL: URL?
    var size: CGFloat = 40
    var useCustom: Bool = false

    @ObservedObject private var store = BeansAvatarStore.shared

    var body: some View {
        Group {
            if useCustom, let custom = BeansImageFileCache.image(at: store.path) {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL {
                CoverImage(url: remoteURL, size: size, cornerRadius: size / 2)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.beansComment)
                    .frame(width: size, height: size)
                    .background(Color.beansGlassFill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// 复用本地图片解码结果，避免设置页/歌词页滚动时反复从磁盘解码大图。
enum BeansImageFileCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(at path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func remove(_ path: String) {
        guard !path.isEmpty else { return }
        cache.removeObject(forKey: path as NSString)
    }

    static func removeAll() {
        cache.removeAllObjects()
    }
}
