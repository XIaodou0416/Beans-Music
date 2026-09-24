import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func performInteractionMutation(
        _ kind: VideoDetailInteractionMutationKind,
        isCurrent: () -> Bool = { true },
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isPlaybackInvalidatedForNavigation else { return false }
        guard !isInteractionMutationActive(kind) else { return false }
        setInteractionMutationActive(true, for: kind)
        interactionMutationRevision += 1
        interactionMessage = nil
        defer {
            if !isPlaybackInvalidatedForNavigation {
                setInteractionMutationActive(false, for: kind)
            }
        }

        do {
            try await operation()
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrent()
            else { return false }
            let confirmation = VideoDetailInteractionMutationConfirmation(
                kind: kind,
                state: interactionState
            )
            await refreshDetailMetadata(preserving: confirmation)
            return true
        } catch {
            guard !isPlaybackInvalidatedForNavigation,
                  isCurrent()
            else { return false }
            interactionMessage = interactionFailureMessage(error)
            return false
        }
    }

    func recoverLikeStateMismatchIfNeeded(_ error: Error, targetState: Bool) -> Bool {
        guard let biliError = error as? BiliAPIError,
              case .api(let code, _) = biliError,
              code == 65004
        else { return false }

        interactionState.isLiked = targetState
        interactionMessage = nil
        return true
    }

    func recoverAmbiguousLikeMutationIfNeeded(
        _ error: Error,
        targetState: Bool,
        aid: Int,
        bvid: String
    ) async -> Bool {
        guard let verifiedState = await verifiedInteractionStateAfterAmbiguousMutation(
            error,
            aid: aid,
            bvid: bvid,
            matches: { $0.isLiked == targetState }
        ) else { return false }
        interactionState = verifiedState
        interactionMessage = nil
        return true
    }

    func recoverAmbiguousCoinMutationIfNeeded(
        _ error: Error,
        expectedCoinCount: Int,
        aid: Int,
        bvid: String
    ) async -> Bool {
        guard let verifiedState = await verifiedInteractionStateAfterAmbiguousMutation(
            error,
            aid: aid,
            bvid: bvid,
            matches: { $0.coinCount >= expectedCoinCount }
        ) else { return false }
        interactionState = verifiedState
        interactionMessage = nil
        return true
    }

    private func verifiedInteractionStateAfterAmbiguousMutation(
        _ error: Error,
        aid: Int,
        bvid: String,
        matches: (VideoInteractionState) -> Bool
    ) async -> VideoInteractionState? {
        guard VideoDetailInteractionReliabilityPolicy.shouldVerifyAmbiguousMutationResult(after: error) else {
            return nil
        }

        for delay in [250_000_000, 650_000_000] as [UInt64] {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return nil
            }
            guard !Task.isCancelled,
                  !isPlaybackInvalidatedForNavigation,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { return nil }
            guard var state = try? await api.fetchVideoInteractionState(aid: aid, bvid: bvid) else {
                continue
            }
            guard isCurrentVideoContext(aid: aid, bvid: bvid) else { return nil }
            if let isFollowing = uploaderProfile?.following {
                state.isFollowing = isFollowing
            }
            if matches(state) {
                return state
            }
        }
        return nil
    }
}
