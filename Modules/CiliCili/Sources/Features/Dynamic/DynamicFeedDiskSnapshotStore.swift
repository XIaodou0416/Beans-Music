import CryptoKit
import Foundation

actor DynamicFeedDiskSnapshotStore {
    static let shared = DynamicFeedDiskSnapshotStore()

    private let directory: URL
    private let freshnessInterval: TimeInterval
    private let maximumSnapshotCount: Int
    private let fileManager: FileManager

    init(
        directory: URL = URL.cachesDirectory.appending(
            path: "DynamicFeedSnapshots",
            directoryHint: .isDirectory
        ),
        freshnessInterval: TimeInterval = 180,
        maximumSnapshotCount: Int = 4,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.freshnessInterval = max(freshnessInterval, 0)
        self.maximumSnapshotCount = max(maximumSnapshotCount, 1)
        self.fileManager = fileManager
    }

    nonisolated static func accountIdentity(for userMID: Int?) -> String? {
        guard let userMID, userMID > 0 else { return nil }
        return "account-\(userMID)"
    }

    func freshData(for identityKey: String, now: Date = Date()) -> Data? {
        let startedAt = Date()
        guard let fileURL = fileURL(for: identityKey),
              let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate
        else {
            ResourceLoadingDiagnostics.shared.record(
                .dynamicSnapshotMiss,
                durationMilliseconds: elapsedMilliseconds(since: startedAt)
            )
            return nil
        }
        let age = now.timeIntervalSince(modifiedAt)
        guard age <= freshnessInterval else {
            try? fileManager.removeItem(at: fileURL)
            ResourceLoadingDiagnostics.shared.record(
                .dynamicSnapshotExpired,
                durationMilliseconds: Int((age * 1_000).rounded())
            )
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            ResourceLoadingDiagnostics.shared.record(
                .dynamicSnapshotMiss,
                durationMilliseconds: elapsedMilliseconds(since: startedAt)
            )
            return nil
        }
        ResourceLoadingDiagnostics.shared.record(
            .dynamicSnapshotHit,
            durationMilliseconds: Int((age * 1_000).rounded()),
            details: ["bytes": data.count.formatted()]
        )
        return data
    }

    func store(_ data: Data, for identityKey: String) {
        guard !data.isEmpty, let fileURL = fileURL(for: identityKey) else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            trimIfNeeded()
            ResourceLoadingDiagnostics.shared.record(
                .dynamicSnapshotSaved,
                value: data.count,
                details: ["bytes": data.count.formatted()]
            )
        } catch {
            return
        }
    }

    func removeData(for identityKey: String) {
        guard let fileURL = fileURL(for: identityKey) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    func clear() {
        try? fileManager.removeItem(at: directory)
    }

    private func fileURL(for identityKey: String) -> URL? {
        let trimmedKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(trimmedKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appending(path: "\(digest).json")
    }

    private func trimIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), files.count > maximumSnapshotCount
        else { return }

        let expiredFiles = files
            .sorted { modificationDate(of: $0) > modificationDate(of: $1) }
            .dropFirst(maximumSnapshotCount)
        expiredFiles.forEach { try? fileManager.removeItem(at: $0) }
    }

    private func modificationDate(of fileURL: URL) -> Date {
        (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    private func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(startedAt) * 1_000).rounded()))
    }
}
