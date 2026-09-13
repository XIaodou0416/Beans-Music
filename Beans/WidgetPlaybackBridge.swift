import Foundation
import UIKit
import WidgetKit

struct WidgetPlaybackState: Codable {
    var songKey: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var progress: Double
    var isPlaying: Bool
    var lyricRaw: String
    var coverFileName: String?
    var colorHex: String?
    var updatedAt: Date
}

enum WidgetPlaybackBridge {
    static let appGroupID = "group.com.beans.music"
    private static let stateKey = "beans.widget.playback.state"
    private static let commandKey = "beans.widget.command"
    private static let coverFileName = "beans-widget-cover.jpg"
    private static var reloadWorkItem: DispatchWorkItem?
    private static var lastReloadUptime = 0.0

    static func publish(
        song: Song,
        progress: Double,
        duration: Double,
        isPlaying: Bool,
        coverData: Data? = nil,
        dominantColor: RGBColor? = nil
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        var state = read(using: defaults) ?? WidgetPlaybackState(
            songKey: song.identityKey,
            title: song.name,
            artist: song.artists,
            album: song.album,
            duration: duration,
            progress: progress,
            isPlaying: isPlaying,
            lyricRaw: "",
            coverFileName: nil,
            colorHex: nil,
            updatedAt: Date()
        )

        let isNewSong = state.songKey != song.identityKey
        state.songKey = song.identityKey
        state.title = song.name
        state.artist = song.artists
        state.album = song.album
        state.duration = max(duration, song.duration)
        state.progress = max(0, progress)
        state.isPlaying = isPlaying
        state.updatedAt = Date()

        if isNewSong {
            state.lyricRaw = ""
            state.coverFileName = nil
            state.colorHex = nil
        }
        if let dominantColor {
            state.colorHex = hex(for: dominantColor)
        }
        if let coverData, !coverData.isEmpty,
           let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
           ) {
            let coverURL = container.appendingPathComponent(coverFileName)
            if (try? coverData.write(to: coverURL, options: .atomic)) != nil {
                state.coverFileName = coverFileName
            }
        }

        save(state, using: defaults)
        requestReload()
    }

    static func updateProgress(progress: Double, isPlaying: Bool) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              var state = read(using: defaults) else { return }
        state.progress = max(0, progress)
        state.isPlaying = isPlaying
        state.updatedAt = Date()
        save(state, using: defaults)
        requestReload()
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: stateKey)
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            try? FileManager.default.removeItem(
                at: container.appendingPathComponent(coverFileName)
            )
        }
        requestReload()
    }

    static func consumeCommand() -> String? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let command = defaults.dictionary(forKey: commandKey),
              let name = command["name"] as? String else {
            return nil
        }
        defaults.removeObject(forKey: commandKey)
        return name
    }

    private static func read(using defaults: UserDefaults) -> WidgetPlaybackState? {
        guard let data = defaults.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(WidgetPlaybackState.self, from: data)
    }

    private static func save(_ state: WidgetPlaybackState, using defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    private static func requestReload() {
        let now = ProcessInfo.processInfo.systemUptime
        guard reloadWorkItem == nil else { return }
        let delay = max(0, 1.5 - (now - lastReloadUptime))
        let work = DispatchWorkItem {
            reloadWorkItem = nil
            lastReloadUptime = ProcessInfo.processInfo.systemUptime
            WidgetCenter.shared.reloadTimelines(ofKind: "BeansWidget")
        }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func hex(for color: RGBColor) -> String {
        let red = Int(max(0, min(1, color.r)) * 255)
        let green = Int(max(0, min(1, color.g)) * 255)
        let blue = Int(max(0, min(1, color.b)) * 255)
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
