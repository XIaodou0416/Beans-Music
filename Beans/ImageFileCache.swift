import UIKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// 主页和“我的”共用的自定义头像，图片只保存在本机沙盒内。
@MainActor
final class BeansAvatarStore: ObservableObject {
    static let shared = BeansAvatarStore()

    @Published private(set) var path: String
    private let defaultsKey = "beans.profile.customAvatarPath"
    private let dataKey = "beans.profile.customAvatarData"
    private let filenameKey = "beans.profile.customAvatarFilename"

    private static var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedPath = defaults.string(forKey: defaultsKey) ?? ""
        let storedFilename = defaults.string(forKey: filenameKey) ?? ""
        let migratedFilename = storedPath.isEmpty ? "" : URL(fileURLWithPath: storedPath).lastPathComponent
        let stableFilenames = [storedFilename, migratedFilename].filter { !$0.isEmpty }

        if let stableURL = stableFilenames.lazy
            .map({ Self.storageDirectory.appendingPathComponent($0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            path = stableURL.path
            defaults.set(stableURL.path, forKey: defaultsKey)
            defaults.set(stableURL.lastPathComponent, forKey: filenameKey)
        } else if !storedPath.isEmpty, FileManager.default.fileExists(atPath: storedPath) {
            path = storedPath
            defaults.set(URL(fileURLWithPath: storedPath).lastPathComponent, forKey: filenameKey)
        } else if let encoded = defaults.string(forKey: dataKey),
                  let data = Data(base64Encoded: encoded),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.88) {
            let fileURL = Self.storageDirectory
                .appendingPathComponent("BeansProfileAvatar.jpg")
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try jpeg.write(to: fileURL, options: .atomic)
                path = fileURL.path
                defaults.set(path, forKey: defaultsKey)
                defaults.set(fileURL.lastPathComponent, forKey: filenameKey)
            } catch {
                path = ""
            }
        } else {
            path = ""
        }
    }

    var isVideo: Bool {
        guard !path.isEmpty,
              let type = UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension) else { return false }
        return type.conforms(to: .movie)
    }

    func save(data: Data) {
        let fileURL = Self.storageDirectory
            .appendingPathComponent("BeansProfileAvatar.jpg")
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.88) else { return }
            if !path.isEmpty, path != fileURL.path {
                try? FileManager.default.removeItem(atPath: path)
                BeansImageFileCache.remove(path)
            }
            try jpeg.write(to: fileURL, options: .atomic)
            path = fileURL.path
            UserDefaults.standard.set(path, forKey: defaultsKey)
            UserDefaults.standard.set(jpeg.base64EncodedString(), forKey: dataKey)
            UserDefaults.standard.set(fileURL.lastPathComponent, forKey: filenameKey)
            BeansImageFileCache.remove(path)
        } catch {
            BeansLogger.shared.log("自定义头像保存失败：\(error.localizedDescription)", level: .warn)
        }
    }

    func saveVideo(data: Data, fileExtension: String) {
        let ext = fileExtension.isEmpty ? "mov" : fileExtension.lowercased()
        let directory = Self.storageDirectory
        let fileURL = directory.appendingPathComponent("BeansProfileAvatar").appendingPathExtension(ext)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !path.isEmpty, path != fileURL.path {
                try? FileManager.default.removeItem(atPath: path)
                BeansImageFileCache.remove(path)
            }
            try data.write(to: fileURL, options: .atomic)
            path = fileURL.path
            UserDefaults.standard.set(path, forKey: defaultsKey)
            UserDefaults.standard.removeObject(forKey: dataKey)
            UserDefaults.standard.set(fileURL.lastPathComponent, forKey: filenameKey)
        } catch {
            BeansLogger.shared.log("自定义视频头像保存失败：\(error.localizedDescription)", level: .warn)
        }
    }

    func clear() {
        if !path.isEmpty {
            try? FileManager.default.removeItem(atPath: path)
            BeansImageFileCache.remove(path)
        }
        path = ""
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: dataKey)
        UserDefaults.standard.removeObject(forKey: filenameKey)
    }
}

struct BeansAvatarView: View {
    let remoteURL: URL?
    var size: CGFloat = 40
    var useCustom: Bool = false

    @ObservedObject private var store = BeansAvatarStore.shared

    var body: some View {
        Group {
            if useCustom, store.isVideo {
                CustomCoverMediaView(url: URL(fileURLWithPath: store.path), isMuted: true)
            } else if useCustom, let custom = BeansImageFileCache.image(at: store.path) {
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

/// 各主页面共用的“我的”快捷入口，始终优先显示用户选择的本地头像。
struct BeansProfileShortcutButton: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("beans.headerAccessoryMode") private var accessoryModeRaw = BeansHeaderAccessoryMode.avatar.rawValue
    var action: () -> Void

    var body: some View {
        Group {
            switch BeansHeaderAccessoryMode(rawValue: accessoryModeRaw) ?? .avatar {
            case .avatar:
                Button {
                    BeansHaptics.tap()
                    action()
                } label: {
                    avatarLabel
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.92))
                .accessibilityLabel(beansLocalized("我的", "Profile"))
            case .themeToggle:
                BeansThemeToggleButton(colorScheme: colorScheme)
            case .hidden:
                EmptyView()
            }
        }
    }

    private var avatarLabel: some View {
        BeansAvatarView(remoteURL: auth.user?.avatarURL, size: 38, useCustom: true)
            .frame(width: 38, height: 38)
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
            }
            .padding(4)
            .background {
                BeansGlass(shape: Circle(), forceLiquid: true)
            }
            .clipShape(Circle())
            .contentShape(Circle())
    }
}

private struct BeansThemeToggleButton: View {
    let colorScheme: ColorScheme
    @State private var touchLocation = CGPoint.zero

    var body: some View {
        Button {
            BeansHaptics.tap()
            NotificationCenter.default.post(
                name: .beansThemeToggleRequested,
                object: BeansThemeToggleRequest(
                    location: touchLocation == .zero
                        ? CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
                        : touchLocation
                )
            )
        } label: {
            Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.beansLabel)
                .frame(width: 38, height: 38)
                .background {
                    BeansGlass(shape: Circle(), forceLiquid: true)
                }
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.92))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    touchLocation = value.startLocation
                }
        )
        .accessibilityLabel(beansLocalized("切换浅深色模式", "Toggle light and dark mode"))
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
