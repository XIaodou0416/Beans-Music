import Foundation
import UIKit
import Combine

final class ChartCoverStore: ObservableObject {
    static let shared = ChartCoverStore()
    @Published private(set) var paths: [String: String]

    private let key = "beans.chartCoverPaths"
    private let dataKey = "beans.chartCoverData"

    private init() {
        paths = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    func image(for provider: SearchProvider) -> UIImage? {
        guard let path = paths[provider.rawValue] else { return nil }
        return UIImage(contentsOfFile: path)
    }

    func set(_ data: Data, for provider: SearchProvider) {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.92) else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansChartCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("\(provider.rawValue).jpg").path
        do {
            try jpeg.write(to: URL(fileURLWithPath: path), options: .atomic)
            paths[provider.rawValue] = path
            UserDefaults.standard.set(paths, forKey: key)
            objectWillChange.send()
        } catch { }
    }

    func backupPayload() -> [String: String] {
        var result: [String: String] = [:]
        for provider in SearchProvider.allCases {
            guard let path = paths[provider.rawValue],
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            result[provider.rawValue] = data.base64EncodedString()
        }
        return result
    }

    func restore(from payload: [String: String]) {
        for provider in SearchProvider.allCases {
            guard let encoded = payload[provider.rawValue], let data = Data(base64Encoded: encoded) else { continue }
            set(data, for: provider)
        }
        UserDefaults.standard.set(payload, forKey: dataKey)
    }

    func clearAll() {
        for path in paths.values { try? FileManager.default.removeItem(atPath: path) }
        paths = [:]
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: dataKey)
        objectWillChange.send()
    }

    func remove(for provider: SearchProvider) {
        if let path = paths.removeValue(forKey: provider.rawValue) {
            try? FileManager.default.removeItem(atPath: path)
        }
        UserDefaults.standard.set(paths, forKey: key)
        objectWillChange.send()
    }
}
