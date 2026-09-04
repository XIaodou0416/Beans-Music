import Foundation
import Combine

struct FeedbackHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let feedbackID: String
    let submittedAt: Date
    let problem: String
    let attachmentCount: Int
}

@MainActor
final class FeedbackHistoryStore: ObservableObject {
    static let shared = FeedbackHistoryStore()

    @Published private(set) var entries: [FeedbackHistoryEntry]

    private let storageKey = "beans.feedback.history"

    private init() {
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
        let entry = FeedbackHistoryEntry(
            id: UUID(),
            feedbackID: feedbackID,
            submittedAt: Self.parseDate(submittedAt) ?? Date(),
            problem: problem.trimmingCharacters(in: .whitespacesAndNewlines),
            attachmentCount: max(0, attachmentCount)
        )
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

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
