import Foundation

struct VideoDetailCoreTaskState {
    var backgroundTasks = [UUID: Task<Void, Never>]()
    var pageLoadingTask: Task<Void, Never>?
    var pageLoadingToken: UUID?
    var detailLoadingTask: Task<Void, Never>?
    var detailLoadingToken: UUID?
    var playVariantSwitchTask: Task<Void, Never>?
    var commentsLoadingTask: Task<Void, Never>?
    var commentsLoadingToken: UUID?
    var startupPlayURLTask: Task<PlayURLData, Error>?
    var startupPlayURLTaskKey: String?
    var startupPlayURLRequestLease: StartupPlayURLRequestLease?
    var startupPlayURLGeneration = 0
    var cloudHistoryResumeTask: Task<VideoHistoryProgress?, Never>?
    var cloudHistoryResumeTaskAid: Int?
}

extension VideoDetailViewModel {
    var backgroundTasks: [UUID: Task<Void, Never>] {
        get { coreTaskState.backgroundTasks }
        set { coreTaskState.backgroundTasks = newValue }
    }

    var pageLoadingTask: Task<Void, Never>? {
        get { coreTaskState.pageLoadingTask }
        set { coreTaskState.pageLoadingTask = newValue }
    }

    var pageLoadingToken: UUID? {
        get { coreTaskState.pageLoadingToken }
        set { coreTaskState.pageLoadingToken = newValue }
    }

    var detailLoadingTask: Task<Void, Never>? {
        get { coreTaskState.detailLoadingTask }
        set { coreTaskState.detailLoadingTask = newValue }
    }

    var detailLoadingToken: UUID? {
        get { coreTaskState.detailLoadingToken }
        set { coreTaskState.detailLoadingToken = newValue }
    }

    var playVariantSwitchTask: Task<Void, Never>? {
        get { coreTaskState.playVariantSwitchTask }
        set { coreTaskState.playVariantSwitchTask = newValue }
    }

    var commentsLoadingTask: Task<Void, Never>? {
        get { coreTaskState.commentsLoadingTask }
        set { coreTaskState.commentsLoadingTask = newValue }
    }

    var commentsLoadingToken: UUID? {
        get { coreTaskState.commentsLoadingToken }
        set { coreTaskState.commentsLoadingToken = newValue }
    }

    var startupPlayURLTask: Task<PlayURLData, Error>? {
        get { coreTaskState.startupPlayURLTask }
        set { coreTaskState.startupPlayURLTask = newValue }
    }

    var startupPlayURLTaskKey: String? {
        get { coreTaskState.startupPlayURLTaskKey }
        set { coreTaskState.startupPlayURLTaskKey = newValue }
    }

    var startupPlayURLRequestLease: StartupPlayURLRequestLease? {
        get { coreTaskState.startupPlayURLRequestLease }
        set { coreTaskState.startupPlayURLRequestLease = newValue }
    }

    var startupPlayURLGeneration: Int {
        get { coreTaskState.startupPlayURLGeneration }
        set { coreTaskState.startupPlayURLGeneration = newValue }
    }

    var cloudHistoryResumeTask: Task<VideoHistoryProgress?, Never>? {
        get { coreTaskState.cloudHistoryResumeTask }
        set { coreTaskState.cloudHistoryResumeTask = newValue }
    }

    var cloudHistoryResumeTaskAid: Int? {
        get { coreTaskState.cloudHistoryResumeTaskAid }
        set { coreTaskState.cloudHistoryResumeTaskAid = newValue }
    }
}
