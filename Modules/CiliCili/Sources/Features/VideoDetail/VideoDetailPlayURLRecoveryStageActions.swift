import Foundation

extension VideoDetailViewModel {
    func applyStartupPlayURLRecoveryIfPossible(
        cid: Int,
        page: Int?
    ) async -> Bool {
        do {
            let startupData = try await fetchStartupPlayURLForRecovery(cid: cid, page: page)
            return await applyRecoveredPlayURLData(
                startupData,
                cid: cid,
                page: page,
                source: "startupRecovery"
            )
        } catch {
            guard !Task.isCancelled else { return false }
            PlayerMetricsLog.record(
                .failed,
                metricsID: detail.bvid,
                title: detail.title,
                message: "startupPlayURLRecovery failed \(error.localizedDescription)"
            )
            return false
        }
    }

    func applyFullPlayURLRecoveryIfPossible(
        cid: Int,
        page: Int?
    ) async -> Bool {
        do {
            let fullData = try await fetchFullPlayURLForRecovery(cid: cid, page: page)
            if await applyRecoveredPlayURLData(
                fullData,
                cid: cid,
                page: page,
                source: "networkRecovery"
            ) {
                return true
            }
            throw BiliAPIError.emptyPlayURL
        } catch {
            guard !Task.isCancelled else { return false }
            PlayerMetricsLog.record(
                .failed,
                metricsID: detail.bvid,
                title: detail.title,
                message: "playURLRecovery failed \(error.localizedDescription)"
            )
            return false
        }
    }
}
