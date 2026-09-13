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
    private static let lastConsumedCommandIDKey = "beans.widget.command.lastConsumedID"
    private static let coverFileName = "beans-widget-cover.jpg"
    private static var reloadWorkItem: DispatchWorkItem?
    private static var lastReloadUptime = 0.0
    private static var lastDiagnosticUptime = 0.0

    static func publish(
        song: Song,
        progress: Double,
        duration: Double,
        isPlaying: Bool,
        coverData: Data? = nil,
        dominantColor: RGBColor? = nil
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            logDiagnostic("App Group UserDefaults 不可用")
            return
        }
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
        let wasPlaying = state.isPlaying
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
            } else {
                logDiagnostic("App Group 封面写入失败")
            }
        } else if coverData != nil {
            logDiagnostic("App Group 容器不可用，无法写入封面")
        }

        guard save(state, using: defaults) else { return }
        defaults.synchronize()
        if defaults.data(forKey: stateKey) == nil {
            logDiagnostic("共享播放状态写入后无法读取")
        } else if isNewSong || wasPlaying != isPlaying {
            logDiagnostic("共享播放状态已写入：字段=11 歌曲=\(titleSummary(state.title)) 播放=\(isPlaying ? "是" : "否")")
        }
        requestReload(force: isNewSong || wasPlaying != isPlaying)
    }

    static func updateProgress(progress: Double, isPlaying: Bool) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              var state = read(using: defaults) else { return }
        state.progress = max(0, progress)
        state.isPlaying = isPlaying
        state.updatedAt = Date()
        guard save(state, using: defaults) else { return }
        defaults.synchronize()
        requestReload()
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            logDiagnostic("App Group UserDefaults 不可用，无法清除状态")
            return
        }
        defaults.removeObject(forKey: stateKey)
        defaults.synchronize()
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
              let commandID = command["id"] as? String,
              let name = command["name"] as? String else {
            return nil
        }
        if defaults.string(forKey: lastConsumedCommandIDKey) == commandID {
            defaults.removeObject(forKey: commandKey)
            defaults.synchronize()
            return nil
        }
        defaults.set(commandID, forKey: lastConsumedCommandIDKey)
        defaults.removeObject(forKey: commandKey)
        defaults.synchronize()
        logDiagnostic("已接收小组件命令：\(name)")
        return name
    }

    private static func read(using defaults: UserDefaults) -> WidgetPlaybackState? {
        guard let data = defaults.data(forKey: stateKey) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetPlaybackState.self, from: data)
        } catch {
            logDiagnostic("共享播放状态解析失败：\(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private static func save(_ state: WidgetPlaybackState, using defaults: UserDefaults) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else {
            logDiagnostic("共享播放状态编码失败")
            return false
        }
        defaults.set(data, forKey: stateKey)
        return true
    }

    private static func requestReload(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if force {
            reloadWorkItem?.cancel()
            reloadWorkItem = nil
            lastReloadUptime = now
            WidgetCenter.shared.reloadTimelines(ofKind: "BeansWidget")
            return
        }
        guard reloadWorkItem == nil,
              now - lastReloadUptime >= 15 else { return }
        let delay = 0.2
        let work = DispatchWorkItem {
            reloadWorkItem = nil
            lastReloadUptime = ProcessInfo.processInfo.systemUptime
            WidgetCenter.shared.reloadTimelines(ofKind: "BeansWidget")
        }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func titleSummary(_ title: String) -> String {
        let normalized = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(normalized.prefix(32))
    }

    private static func logDiagnostic(_ message: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDiagnosticUptime >= 2 else { return }
        lastDiagnosticUptime = now
        BeansLogger.shared.log("小组件：\(message)", level: .debug)
    }

    private static func hex(for color: RGBColor) -> String {
        let red = Int(max(0, min(1, color.r)) * 255)
        let green = Int(max(0, min(1, color.g)) * 255)
        let blue = Int(max(0, min(1, color.b)) * 255)
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
