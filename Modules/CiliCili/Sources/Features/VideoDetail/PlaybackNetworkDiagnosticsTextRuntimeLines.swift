import Foundation

@MainActor
extension PlaybackNetworkDiagnosticsTextBuilder {
    func appendCacheLines(to lines: inout [String]) {
        guard let cacheSummary else { return }
        lines.append("API SWR 缓存：\(cacheSummary.apiMemory.count) 条，\(PlaybackNetworkDiagnosticFormat.formattedBytes(cacheSummary.apiMemory.estimatedBytes))")
        lines.append("API SWR 命中：fresh \(cacheSummary.apiMemory.hits)，stale \(cacheSummary.apiMemory.staleHits)，miss \(cacheSummary.apiMemory.misses)")
        lines.append("媒体缓存：\(cacheSummary.progressiveMedia.entryCount) 段，\(PlaybackNetworkDiagnosticFormat.formattedBytes(cacheSummary.progressiveMedia.estimatedBytes))")
        lines.append("图片缓存：\(cacheSummary.image.memoryEntryCount) 张，\(PlaybackNetworkDiagnosticFormat.formattedBytes(cacheSummary.image.diskUsage))")
    }

    func appendPlayerLines(to lines: inout [String]) {
        lines.append("播放器状态：\(playerStateTitle)")
        lines.append("播放器引擎：\(playerViewModel?.engineDiagnostics.engineName ?? "未知")")
        lines.append("解码路径：\(playerViewModel?.engineDiagnostics.decodePath.title ?? "未知")")
        if let diagnostics = playerViewModel?.engineDiagnostics {
            lines.append("实际编码：\(diagnostics.codec ?? "未知")")
            lines.append("请求硬解：\(diagnostics.hardwareDecodeRequested ? "是" : "否")")
            lines.append("硬解兼容：\(PlaybackNetworkPlayerDiagnosticSnapshot.hardwareCompatibilityTitle(diagnostics.isHardwareDecodeCompatible))")
            lines.append("异步硬解：\(diagnostics.asynchronousDecompressionEnabled ? "开启" : "关闭")")
            if diagnostics.hlsVideoVariantCount > 0 {
                lines.append("HLS 档位：\(PlaybackNetworkDiagnosticFormat.hlsVariantText(diagnostics))")
            }
        } else {
            lines.append("实际编码：未知")
            lines.append("请求硬解：未知")
            lines.append("硬解兼容：未知")
            lines.append("异步硬解：未知")
        }
        lines.append("准备耗时：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel?.prepareElapsedMilliseconds))")
        lines.append("首帧耗时：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel?.firstFrameElapsedMilliseconds))")
        lines.append("缓冲次数：\(playerViewModel?.bufferingCount ?? 0)")
        lines.append("最近缓冲：\(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel?.lastBufferingElapsedMilliseconds))")
    }

    func appendEnvironmentLines(to lines: inout [String]) {
        lines.append("网络类型：\(playbackEnvironment.networkClass.diagnosticTitle)")
        lines.append("省电模式：\(playbackEnvironment.isLowPowerModeEnabled ? "开启" : "关闭")")
        lines.append("温控限制：\(playbackEnvironment.isThermallyConstrained ? "已触发" : "未触发")")
        lines.append("AVPlayer 启动链路优化：已启用")
        lines.append("PiliPlus 风格 AV1 取流：已启用")
    }

    func appendErrorLines(to lines: inout [String]) {
        appendOptional("播放器错误", playerViewModel?.errorMessage, to: &lines)
        appendOptional("降级信息", diagnosticsStore.playbackFallbackMessage, to: &lines)
    }

    var playerStateTitle: String {
        guard let playerViewModel else { return "等待播放器" }
        if playerViewModel.errorMessage?.isEmpty == false {
            return "播放错误"
        }
        if playerViewModel.isPreparing {
            return "准备中"
        }
        if playerViewModel.isBuffering {
            return "缓冲中"
        }
        if playerViewModel.isPlaying {
            return "播放中"
        }
        return "暂停/待播"
    }
}
