import Foundation
import Combine

struct FeedbackRemoteAttachment: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let originalName: String
    let mimeType: String
    let size: Int
    let url: String

    var id: String { url }
    var isVideo: Bool { mimeType.hasPrefix("video/") }

    enum CodingKeys: String, CodingKey {
        case name
        case originalName = "original_name"
        case mimeType = "mime_type"
        case size
        case url
    }

    init(
        name: String,
        originalName: String,
        mimeType: String,
        size: Int,
        url: String
    ) {
        self.name = name
        self.originalName = originalName
        self.mimeType = mimeType
        self.size = size
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        originalName = try container.decodeIfPresent(String.self, forKey: .originalName) ?? name
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        url = try container.decode(String.self, forKey: .url)
    }
}

struct FeedbackReply: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let feedbackID: String
    let text: String
    let attachments: [FeedbackRemoteAttachment]
    let sentAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case feedbackID = "feedback_id"
        case text
        case attachments
        case sentAt = "sent_at"
    }

    init(
        id: String,
        feedbackID: String,
        text: String,
        attachments: [FeedbackRemoteAttachment],
        sentAt: String
    ) {
        self.id = id
        self.feedbackID = feedbackID
        self.text = text
        self.attachments = attachments
        self.sentAt = sentAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        feedbackID = try container.decodeIfPresent(String.self, forKey: .feedbackID) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        attachments = try container.decodeIfPresent([FeedbackRemoteAttachment].self, forKey: .attachments) ?? []
        sentAt = try container.decodeIfPresent(String.self, forKey: .sentAt) ?? ""
    }
}

struct FeedbackServerRecord: Decodable, Sendable {
    let id: String
    let submittedAt: String
    let problem: String
    let attachmentCount: Int
    let replies: [FeedbackReply]

    enum CodingKeys: String, CodingKey {
        case id
        case submittedAt = "submitted_at"
        case problem
        case attachments
        case replies
    }

    init(
        id: String,
        submittedAt: String,
        problem: String,
        attachmentCount: Int,
        replies: [FeedbackReply]
    ) {
        self.id = id
        self.submittedAt = submittedAt
        self.problem = problem
        self.attachmentCount = max(0, attachmentCount)
        self.replies = replies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt) ?? ""
        problem = try container.decodeIfPresent(String.self, forKey: .problem) ?? ""
        let attachments = try container.decodeIfPresent(
            [FeedbackRemoteAttachment].self,
            forKey: .attachments
        ) ?? []
        attachmentCount = attachments.count
        replies = try container.decodeIfPresent([FeedbackReply].self, forKey: .replies) ?? []
    }
}

struct FeedbackHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let feedbackID: String
    let submittedAt: Date
    let problem: String
    let attachmentCount: Int
    var replies: [FeedbackReply]

    init(
        id: UUID = UUID(),
        feedbackID: String,
        submittedAt: Date,
        problem: String,
        attachmentCount: Int,
        replies: [FeedbackReply] = []
    ) {
        self.id = id
        self.feedbackID = feedbackID
        self.submittedAt = submittedAt
        self.problem = problem
        self.attachmentCount = max(0, attachmentCount)
        self.replies = replies
    }

    private enum CodingKeys: String, CodingKey {
        case id, feedbackID, submittedAt, problem, attachmentCount, replies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        feedbackID = try container.decode(String.self, forKey: .feedbackID)
        submittedAt = try container.decode(Date.self, forKey: .submittedAt)
        problem = try container.decode(String.self, forKey: .problem)
        attachmentCount = try container.decodeIfPresent(Int.self, forKey: .attachmentCount) ?? 0
        replies = try container.decodeIfPresent([FeedbackReply].self, forKey: .replies) ?? []
    }
}

@MainActor
final class FeedbackHistoryStore: ObservableObject {
    static let shared = FeedbackHistoryStore()

    @Published private(set) var entries: [FeedbackHistoryEntry]
    @Published private(set) var unreadReplyCount = 0

    private let storageKey = "beans.feedback.history"
    private let seenReplyIDsKey = "beans.feedback.seenReplyIDs"
    private var seenReplyIDs: Set<String>

    private init() {
        seenReplyIDs = Set(UserDefaults.standard.stringArray(forKey: seenReplyIDsKey) ?? [])
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([FeedbackHistoryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = saved.sorted { $0.submittedAt > $1.submittedAt }
    }

    func record(
        feedbackID: String,
        submittedAt: String?,
        problem: String,
        attachmentCount: Int
    ) {
        let oldReplies = entries.first { $0.feedbackID == feedbackID }?.replies ?? []
        let entry = FeedbackHistoryEntry(
            feedbackID: feedbackID,
            submittedAt: Self.parseDate(submittedAt) ?? Date(),
            problem: problem.trimmingCharacters(in: .whitespacesAndNewlines),
            attachmentCount: max(0, attachmentCount),
            replies: oldReplies
        )
        entries.removeAll { $0.feedbackID == feedbackID }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(100))
        save()
    }

    func remove(_ entry: FeedbackHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func refreshFromServer() async {
        guard let records = try? await DeviceReporter.shared.fetchFeedbackHistory() else { return }
        merge(records: records, notify: false)
    }

    func receiveServerReplies(_ replies: [FeedbackReply]) {
        guard !replies.isEmpty else { return }
        let records = replies.map {
            FeedbackServerRecord(
                id: $0.feedbackID,
                submittedAt: "",
                problem: "",
                attachmentCount: 0,
                replies: [$0]
            )
        }
        merge(records: records, notify: true)
    }

    func markRepliesRead() {
        unreadReplyCount = 0
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func saveSeenReplyIDs() {
        UserDefaults.standard.set(Array(seenReplyIDs), forKey: seenReplyIDsKey)
    }

    private func merge(records: [FeedbackServerRecord], notify: Bool) {
        var newReplyCount = 0
        for record in records {
            let existingIndex = entries.firstIndex { $0.feedbackID == record.id }
            let oldEntry = existingIndex.map { entries[$0] }
            let mergedReplies = mergeReplies(
                oldEntry?.replies ?? [],
                record.replies,
                notify: notify,
                newReplyCount: &newReplyCount
            )
            let submittedAt = Self.parseDate(record.submittedAt)
                ?? oldEntry?.submittedAt
                ?? Date()
            let problem = record.problem.isEmpty ? (oldEntry?.problem ?? "") : record.problem
            let attachmentCount = record.attachmentCount > 0
                ? record.attachmentCount
                : (oldEntry?.attachmentCount ?? 0)
            let entry = FeedbackHistoryEntry(
                id: oldEntry?.id ?? UUID(),
                feedbackID: record.id,
                submittedAt: submittedAt,
                problem: problem,
                attachmentCount: attachmentCount,
                replies: mergedReplies
            )
            if let existingIndex {
                entries[existingIndex] = entry
            } else {
                entries.append(entry)
            }
        }
        entries.sort { $0.submittedAt > $1.submittedAt }
        entries = Array(entries.prefix(100))
        save()
        saveSeenReplyIDs()
        if newReplyCount > 0 {
            unreadReplyCount += newReplyCount
            ToastCenter.shared.show(
                beansLocalized(
                    "收到 \(newReplyCount) 条工单回复",
                    "Received \(newReplyCount) ticket repl\(newReplyCount == 1 ? "y" : "ies")"
                ),
                duration: 3
            )
        }
    }

    private func mergeReplies(
        _ existing: [FeedbackReply],
        _ incoming: [FeedbackReply],
        notify: Bool,
        newReplyCount: inout Int
    ) -> [FeedbackReply] {
        var result = existing
        var knownIDs = Set(existing.map(\.id))
        for reply in incoming where knownIDs.insert(reply.id).inserted {
            result.append(reply)
            if !seenReplyIDs.contains(reply.id) {
                if notify {
                    newReplyCount += 1
                }
                seenReplyIDs.insert(reply.id)
            }
        }
        return result.sorted { $0.sentAt < $1.sentAt }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
