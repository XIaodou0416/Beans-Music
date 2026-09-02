import Foundation
import UIKit
import Combine

struct ChartCoverTarget: Identifiable, Hashable {
    let provider: SearchProvider
    let index: Int

    var id: String { ChartCoverStore.storageKey(provider: provider, index: index) }
}

/// Stores one optional cover for each visible chart slot on each platform.
final class ChartCoverStore: ObservableObject {
    static let shared = ChartCoverStore()
    @Published private(set) var paths: [String: String]

    private let pathsKey = "beans.chartCoverPaths"
    private let legacyDataKey = "beans.chartCoverData"
    private let directoryName = "BeansChartCovers"

    private init() {
        paths = UserDefaults.standard.dictionary(forKey: pathsKey) as? [String: String] ?? [:]
    }

    static func storageKey(provider: SearchProvider, index: Int) -> String {
        "\(providerStorageName(provider))-\(max(0, index))"
    }

    private static func providerStorageName(_ provider: SearchProvider) -> String {
        switch provider {
        case .netease: return "netease"
        case .qq: return "qq"
        case .kugou: return "kugou"
        }
    }

    private func legacyKey(for provider: SearchProvider) -> String {
        provider.rawValue
    }

    func image(for provider: SearchProvider, index: Int) -> UIImage? {
        let key = Self.storageKey(provider: provider, index: index)
        if let path = paths[key], let image = UIImage(contentsOfFile: path) {
            return image
        }
        // Keep covers created by the previous per-platform version visible in slot 0.
        guard index == 0, let path = paths[legacyKey(for: provider)] else { return nil }
        return UIImage(contentsOfFile: path)
    }

    func set(_ data: Data, for provider: SearchProvider, index: Int) {
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.92) else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = Self.storageKey(provider: provider, index: index)
        let path = directory.appendingPathComponent("\(key).jpg").path
        do {
            try jpeg.write(to: URL(fileURLWithPath: path), options: .atomic)
            if let previous = paths[key], previous != path {
                try? FileManager.default.removeItem(atPath: previous)
            }
            paths[key] = path
            UserDefaults.standard.set(paths, forKey: pathsKey)
        } catch {
            return
        }
    }

    func remove(for provider: SearchProvider, index: Int) {
        let key = Self.storageKey(provider: provider, index: index)
        if let path = paths.removeValue(forKey: key) {
            try? FileManager.default.removeItem(atPath: path)
        }
        // Also remove the old format if the user is clearing the migrated slot.
        if index == 0, let path = paths.removeValue(forKey: legacyKey(for: provider)) {
            try? FileManager.default.removeItem(atPath: path)
        }
        UserDefaults.standard.set(paths, forKey: pathsKey)
    }

    func hasCover(for provider: SearchProvider, index: Int) -> Bool {
        image(for: provider, index: index) != nil
    }

    /// Export image bytes rather than sandbox paths so restores work across installations.
    func backupPayload() -> [String: String] {
        var result: [String: String] = [:]
        for (key, path) in paths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            result[key] = data.base64EncodedString()
        }
        return result
    }

    func restore(from payload: [String: String]) {
        for (key, encoded) in payload {
            guard let data = Data(base64Encoded: encoded) else { continue }
            if let target = Self.target(from: key) {
                set(data, for: target.provider, index: target.index)
            } else if let provider = SearchProvider(rawValue: key) {
                // Backward compatibility with the first per-platform backup format.
                set(data, for: provider, index: 0)
            }
        }
        UserDefaults.standard.removeObject(forKey: legacyDataKey)
    }

    private static func target(from key: String) -> ChartCoverTarget? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let index = Int(parts[1]), index >= 0 else { return nil }
        let provider: SearchProvider?
        switch parts[0] {
        case "netease": provider = .netease
        case "qq": provider = .qq
        case "kugou": provider = .kugou
        default: provider = nil
        }
        guard let provider else { return nil }
        return ChartCoverTarget(provider: provider, index: index)
    }

    func clearAll() {
        for path in paths.values { try? FileManager.default.removeItem(atPath: path) }
        paths = [:]
        UserDefaults.standard.removeObject(forKey: pathsKey)
        UserDefaults.standard.removeObject(forKey: legacyDataKey)
    }
}
