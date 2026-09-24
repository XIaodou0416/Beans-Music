import Foundation

struct VideoDetailPlaybackWarmupTaskState {
    var hlsRenditionPrebuildTask: Task<Void, Never>?
    var hlsRenditionPrebuildGeneration = 0
    var seekWarmupTasks: [String: Task<Void, Never>] = [:]
    var seekWarmupTokens: [String: UUID] = [:]
    var seekWarmupTaskOrder: [String] = []
    var recentSeekWarmupKeys = Set<String>()
    var recentSeekWarmupKeyOrder: [String] = []
}

extension VideoDetailViewModel {
    var hlsRenditionPrebuildTask: Task<Void, Never>? {
        get { playbackWarmupTaskState.hlsRenditionPrebuildTask }
        set { playbackWarmupTaskState.hlsRenditionPrebuildTask = newValue }
    }

    var hlsRenditionPrebuildGeneration: Int {
        get { playbackWarmupTaskState.hlsRenditionPrebuildGeneration }
        set { playbackWarmupTaskState.hlsRenditionPrebuildGeneration = newValue }
    }

    var seekWarmupTasks: [String: Task<Void, Never>] {
        get { playbackWarmupTaskState.seekWarmupTasks }
        set { playbackWarmupTaskState.seekWarmupTasks = newValue }
    }

    var seekWarmupTokens: [String: UUID] {
        get { playbackWarmupTaskState.seekWarmupTokens }
        set { playbackWarmupTaskState.seekWarmupTokens = newValue }
    }

    var seekWarmupTaskOrder: [String] {
        get { playbackWarmupTaskState.seekWarmupTaskOrder }
        set { playbackWarmupTaskState.seekWarmupTaskOrder = newValue }
    }

    var recentSeekWarmupKeys: Set<String> {
        get { playbackWarmupTaskState.recentSeekWarmupKeys }
        set { playbackWarmupTaskState.recentSeekWarmupKeys = newValue }
    }

    var recentSeekWarmupKeyOrder: [String] {
        get { playbackWarmupTaskState.recentSeekWarmupKeyOrder }
        set { playbackWarmupTaskState.recentSeekWarmupKeyOrder = newValue }
    }
}
