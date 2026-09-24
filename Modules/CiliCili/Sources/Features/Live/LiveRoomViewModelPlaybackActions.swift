import Foundation

extension LiveRoomViewModel {
    func showLivePlaybackDiagnostics() {
        isShowingLivePlaybackDiagnostics = true
    }

    func refreshLiveToLatest() {
        guard !isRefreshingLiveEdge else { return }
        isRefreshingLiveEdge = true

        if playerViewModel?.jumpToLiveEdge() == true {
            finishLiveEdgeRefresh(after: 450_000_000)
            return
        }

        guard roomID > 0 else {
            isRefreshingLiveEdge = false
            reload()
            return
        }

        let generation = currentLoadGeneration
        liveEdgeRefreshTask?.cancel()
        liveEdgeRefreshTask = Task { [weak self] in
            await self?.reloadCurrentStreamAtLiveEdge(generation: generation)
        }
    }

    private func reloadCurrentStreamAtLiveEdge(generation: Int) async {
        defer {
            if isCurrentLoad(generation) {
                isRefreshingLiveEdge = false
                liveEdgeRefreshTask = nil
            }
        }

        let previousCandidate = streamCandidates.indices.contains(currentCandidateIndex)
            ? streamCandidates[currentCandidateIndex]
            : nil
        do {
            async let streamResultTask = api.fetchLiveStreamInfo(
                roomID: roomID,
                quality: selectedQualityQN
            )
            async let streamHTTPHeadersTask = api.livePlaybackHTTPHeaders(roomID: roomID)
            let (streamResult, streamHTTPHeaders) = try await (streamResultTask, streamHTTPHeadersTask)
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }

            let candidates = LiveStreamStartupHealthMemory.shared
                .orderedStartupCandidates(streamResult.candidates)
            guard !candidates.isEmpty else {
                streamFallbackMessage = "暂时无法刷新直播进度"
                return
            }

            self.streamHTTPHeaders = streamHTTPHeaders
            streamCandidates = candidates
            availableQualities = streamResult.playableQualities
            currentCandidateIndex = Self.preferredCandidateIndex(
                in: candidates,
                preferredQuality: selectedQualityQN,
                preferredSource: previousCandidate
            )
            let candidate = streamCandidates[currentCandidateIndex]
            selectedQualityQN = candidate.currentQN ?? selectedQualityQN
            updateStreamMenuItems()
            updateQualityMenuItems()
            streamFallbackMessage = "正在刷新到直播最新进度"
            installPlayer(for: candidate, generation: generation)
            state = .loaded
            playerViewModel?.play()
        } catch {
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            streamFallbackMessage = "刷新直播进度失败：\(error.localizedDescription)"
        }
    }

    private func finishLiveEdgeRefresh(after delay: UInt64) {
        liveEdgeRefreshTask?.cancel()
        liveEdgeRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.isRefreshingLiveEdge = false
            self.liveEdgeRefreshTask = nil
        }
    }

    func installPlayer(
        for candidate: LiveStreamURLCandidate,
        generation: Int,
        allowSlowStartupRouteSwitch: Bool = true
    ) {
        guard isCurrentLoad(generation) else { return }
        startupWatchdogTask?.cancel()
        slowStartupRouteSwitchTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        playerViewModel?.onPlaybackFailure = nil
        playerViewModel?.stop()

        let startupStartedAt = Date()

        let viewModel = PlayerStateViewModel(
            videoURL: candidate.url,
            audioURL: nil,
            videoStream: nil,
            audioStream: nil,
            title: title,
            referer: "https://live.bilibili.com/\(roomID)",
            isLiveStream: true,
            isLiveHLS: candidate.isLikelyHLS,
            liveHLSFormat: candidate.formatName,
            metricsID: "live-\(roomID)",
            httpHeaders: streamHTTPHeaders.isEmpty ? nil : streamHTTPHeaders,
            engine: DefaultPlayerRenderingEngine.make()
        )
        viewModel.onPlaybackFailure = { [weak self] message in
            self?.handlePlaybackFailure(message: message, generation: generation)
        }
        viewModel.onFirstFramePresented = { [weak self, weak viewModel] in
            guard let self,
                  let viewModel,
                  self.isCurrentLoad(generation),
                  self.playerViewModel === viewModel
            else { return }
            self.handleLiveStartupFirstFrame(
                for: candidate,
                playerViewModel: viewModel,
                generation: generation,
                startedAt: startupStartedAt
            )
        }
        playerViewModel = viewModel
        if candidate.isLikelyHLS {
            let usesImmediatePlayback = LiveHLSFastStartPolicy.usesImmediatePlayback(
                isDirectLiveHLS: true,
                isLiveStream: true,
                isStartupFastStartActive: true
            )
            let initialLiveEdgeSeek = LiveHLSFastStartPolicy.defersInitialLiveEdgeSeek(
                streamFormat: candidate.formatName
            ) ? "deferred" : "edge"
            PlayerMetricsLog.record(
                .startupScheduler,
                metricsID: "live-\(roomID)",
                title: title,
                message: "liveHLSFastStart=on protocol=\(candidate.protocolName ?? "-") format=\(candidate.formatName ?? "-") immediatePlay=\(usesImmediatePlayback) initialEdgeSeek=\(initialLiveEdgeSeek)"
            )
        }
        refreshLiveDanmakuDiagnosticsRenderState()
        updateStreamMenuItems()
        updateQualityMenuItems()
        scheduleStartupWatchdog(for: viewModel, candidate: candidate, generation: generation)
        if allowSlowStartupRouteSwitch {
            scheduleSlowStartupRouteSwitch(for: viewModel, candidate: candidate, generation: generation)
        } else {
            slowStartupRouteSwitchStatus = "已切换备用线路，等待首帧"
        }
        schedulePlaybackStallWatchdog(for: viewModel, generation: generation)
    }

    func handlePlaybackFailure(message: String?, generation: Int) {
        guard isCurrentLoad(generation) else { return }
        startupWatchdogTask?.cancel()
        slowStartupRouteSwitchTask?.cancel()
        if streamCandidates.indices.contains(currentCandidateIndex) {
            LiveStreamStartupHealthMemory.shared.recordStartupFailure(
                for: streamCandidates[currentCandidateIndex]
            )
        }
        guard currentCandidateIndex + 1 < streamCandidates.count else {
            streamFallbackMessage = nil
            playerViewModel?.onPlaybackFailure = nil
            playerViewModel?.stop()
            playerViewModel = nil
            state = .failed(message ?? "这个直播流暂时无法播放")
            return
        }

        currentCandidateIndex += 1
        streamFallbackMessage = "正在切换到 \(currentStreamTitle ?? "备用直播源")"
        state = .loading
        installPlayer(for: streamCandidates[currentCandidateIndex], generation: generation)
        state = .loaded
        playerViewModel?.play()
    }

    func selectStreamCandidate(id: Int) {
        guard streamCandidates.indices.contains(id), id != currentCandidateIndex else { return }
        let generation = currentLoadGeneration
        currentCandidateIndex = id
        updateStreamMenuItems()
        streamFallbackMessage = "正在切换到 \(currentStreamTitle ?? "直播线路")"
        state = .loading
        installPlayer(for: streamCandidates[id], generation: generation)
        state = .loaded
        playerViewModel?.play()
    }

    func selectQuality(qn: Int) {
        guard qn > 0, qn != selectedQualityQN || currentQualityTitle == nil else { return }
        let generation = currentLoadGeneration
        qualitySwitchTask?.cancel()
        qualitySwitchTask = Task { [weak self] in
            await self?.switchQuality(to: qn, generation: generation)
        }
    }

    func switchQuality(to qn: Int, generation: Int) async {
        guard isCurrentLoad(generation), roomID > 0 else { return }
        let previousCandidate = streamCandidates.indices.contains(currentCandidateIndex)
            ? streamCandidates[currentCandidateIndex]
            : nil
        streamFallbackMessage = "正在切换到 \(LiveStreamQuality.defaultTitle(for: qn))"
        state = .loading
        do {
            let streamResult = try await api.fetchLiveStreamInfo(roomID: roomID, quality: qn)
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            guard !streamResult.candidates.isEmpty else {
                streamFallbackMessage = "这个画质暂时不可用"
                state = .loaded
                return
            }
            let candidates = LiveStreamStartupHealthMemory.shared
                .orderedStartupCandidates(streamResult.candidates)
            streamCandidates = candidates
            availableQualities = streamResult.playableQualities
            currentCandidateIndex = Self.preferredCandidateIndex(
                in: candidates,
                preferredQuality: qn,
                preferredSource: previousCandidate
            )
            let selectedCandidate = streamCandidates[currentCandidateIndex]
            selectedQualityQN = qn
            updateStreamMenuItems()
            updateQualityMenuItems()
            if selectedCandidate.currentQN != qn {
                streamFallbackMessage = "该画质暂不可用，已切到 \(currentQualityTitle ?? "可用画质")"
            } else {
                streamFallbackMessage = nil
            }
            installPlayer(for: selectedCandidate, generation: generation)
            state = .loaded
            playerViewModel?.play()
        } catch {
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            streamFallbackMessage = "画质切换失败：\(error.localizedDescription)"
            updateQualityMenuItems()
            state = playerViewModel == nil ? .failed(streamFallbackMessage ?? "画质切换失败") : .loaded
        }
    }

    func scheduleStartupWatchdog(
        for viewModel: PlayerStateViewModel,
        candidate: LiveStreamURLCandidate,
        generation: Int
    ) {
        let hasRecentFailure = LiveStreamStartupHealthMemory.shared.hasRecentFailure(for: candidate)
        let delaySeconds = hasRecentFailure
            ? LivePlaybackPolicy.knownUnhealthyHostWatchdogSeconds
            : 10
        if hasRecentFailure {
            PlayerMetricsLog.record(
                .startupScheduler,
                metricsID: "live-\(roomID)",
                title: title,
                message: "liveCDN=shortWatchdog host=\(candidate.url.host ?? "-") timeout=\(String(format: "%.1f", delaySeconds))s"
            )
        }
        startupWatchdogTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let viewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === viewModel,
                      !viewModel.hasPresentedPlayback
                else { return }
                self.handlePlaybackFailure(message: "直播流首帧加载超时", generation: generation)
            }
        }
    }

    private func handleLiveStartupFirstFrame(
        for candidate: LiveStreamURLCandidate,
        playerViewModel: PlayerStateViewModel,
        generation: Int,
        startedAt: Date
    ) {
        guard isCurrentLoad(generation), self.playerViewModel === playerViewModel else { return }
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
        slowStartupRouteSwitchTask?.cancel()
        slowStartupRouteSwitchTask = nil

        let elapsedMilliseconds = max(
            0,
            Int((Date().timeIntervalSince(startedAt) * 1_000.0).rounded())
        )
        LiveStreamStartupHealthMemory.shared.recordStartupResult(
            for: candidate,
            firstFrameMilliseconds: elapsedMilliseconds
        )

        let routeNumber = currentCandidateIndex + 1
        slowStartupRouteSwitchStatus = "线路 \(routeNumber) 首帧 \(elapsedMilliseconds)ms"
        PlayerMetricsLog.record(
            .startupScheduler,
            metricsID: "live-\(roomID)",
            title: title,
            message: "liveSlowStartSwitch=firstFrame route=\(routeNumber) host=\(candidate.url.host ?? "-") elapsed=\(elapsedMilliseconds)ms"
        )
    }

    private func scheduleSlowStartupRouteSwitch(
        for viewModel: PlayerStateViewModel,
        candidate: LiveStreamURLCandidate,
        generation: Int
    ) {
        guard let plan = LiveSlowStartupRouteSwitchPlan.make(
            candidates: streamCandidates,
            primaryIndex: currentCandidateIndex
        ), plan.primaryIndex == currentCandidateIndex else {
            slowStartupRouteSwitchStatus = "未触发：没有不同节点的 TS 备用线路"
            return
        }

        let fallbackCandidate = streamCandidates[plan.fallbackIndex]
        let delayMilliseconds = LivePlaybackPolicy.slowStartupRouteSwitchDelayMilliseconds
        let delayText = String(format: "%.1f", Double(delayMilliseconds) / 1_000)
        slowStartupRouteSwitchStatus = "观察线路 \(plan.primaryIndex + 1)，超过 \(delayText) 秒自动换线"
        PlayerMetricsLog.record(
            .startupScheduler,
            metricsID: "live-\(roomID)",
            title: title,
            message: "liveSlowStartSwitch=armed primary=\(plan.primaryIndex + 1) fallback=\(plan.fallbackIndex + 1) host=\(candidate.url.host ?? "-") fallbackHost=\(fallbackCandidate.url.host ?? "-") timeout=\(delayText)s"
        )

        slowStartupRouteSwitchTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(
                nanoseconds: LivePlaybackPolicy.slowStartupRouteSwitchDelayNanoseconds
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let viewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === viewModel,
                      !viewModel.hasPresentedPlayback,
                      self.currentCandidateIndex == plan.primaryIndex,
                      self.streamCandidates.indices.contains(plan.fallbackIndex)
                else { return }

                LiveStreamStartupHealthMemory.shared.recordStartupResult(
                    for: candidate,
                    firstFrameMilliseconds: Int(
                        LivePlaybackPolicy.slowStartupRouteSwitchDelayNanoseconds / 1_000_000
                    )
                )
                self.currentCandidateIndex = plan.fallbackIndex
                self.updateStreamMenuItems()
                self.updateQualityMenuItems()
                self.streamFallbackMessage = "首帧较慢，正在切换到备用直播线路"
                self.slowStartupRouteSwitchStatus = "线路 \(plan.primaryIndex + 1) 超过 \(delayText) 秒未出画面，切换线路 \(plan.fallbackIndex + 1)"
                PlayerMetricsLog.record(
                    .startupScheduler,
                    metricsID: "live-\(self.roomID)",
                    title: self.title,
                    message: "liveSlowStartSwitch=triggered primary=\(plan.primaryIndex + 1) fallback=\(plan.fallbackIndex + 1) host=\(candidate.url.host ?? "-") fallbackHost=\(fallbackCandidate.url.host ?? "-") elapsed=\(delayMilliseconds)ms"
                )
                self.installPlayer(
                    for: self.streamCandidates[plan.fallbackIndex],
                    generation: generation,
                    allowSlowStartupRouteSwitch: false
                )
                self.state = .loaded
                self.playerViewModel?.play()
            }
        }
    }

    func schedulePlaybackStallWatchdog(for viewModel: PlayerStateViewModel, generation: Int) {
        playbackStallWatchdogTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let viewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === viewModel,
                      viewModel.hasPresentedPlayback
                else { return }
            }

            var lastTime = await MainActor.run { viewModel?.currentTime ?? 0 }
            var stalledChecks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                let shouldSwitch = await MainActor.run { () -> Bool in
                    guard let self,
                          let viewModel,
                          self.isCurrentLoad(generation),
                          self.playerViewModel === viewModel
                    else { return false }
                    if viewModel.errorMessage != nil {
                        return true
                    }
                    guard viewModel.wantsAutoplay else {
                        stalledChecks = 0
                        lastTime = viewModel.currentTime
                        return false
                    }
                    let currentTime = viewModel.currentTime
                    if viewModel.isBuffering || abs(currentTime - lastTime) < 0.1 {
                        stalledChecks += 1
                    } else {
                        stalledChecks = 0
                    }
                    lastTime = currentTime
                    return stalledChecks >= 2 && self.currentCandidateIndex + 1 < self.streamCandidates.count
                }
                guard shouldSwitch else { continue }
                await MainActor.run {
                    self?.handlePlaybackFailure(message: "直播流长时间无画面", generation: generation)
                }
                return
            }
        }
    }

    func updateStreamMenuItems() {
        streamMenuItems = streamCandidates.indices.map { index in
            LiveStreamMenuItem(
                id: index,
                title: Self.streamTitle(for: streamCandidates[index], index: index),
                isSelected: index == currentCandidateIndex
            )
        }
    }

    func updateQualityMenuItems() {
        let currentQN = streamCandidates.indices.contains(currentCandidateIndex)
            ? streamCandidates[currentCandidateIndex].currentQN
            : selectedQualityQN
        let qualities = availableQualities.isEmpty
            ? LiveStreamQuality.merged(
                streamCandidates.compactMap { candidate in
                    candidate.currentQN.map {
                        LiveStreamQuality(qn: $0, description: candidate.qualityTitle)
                    }
                }
            )
            : availableQualities
        qualityMenuItems = qualities.map { quality in
            LiveStreamQualityMenuItem(
                qn: quality.qn,
                title: quality.title,
                isSelected: quality.qn == currentQN || (currentQN == nil && quality.qn == selectedQualityQN)
            )
        }
        if let currentQN {
            currentQualityTitle = qualities.first(where: { $0.qn == currentQN })?.title
                ?? LiveStreamQuality.defaultTitle(for: currentQN)
        } else {
            currentQualityTitle = nil
        }
    }
}
