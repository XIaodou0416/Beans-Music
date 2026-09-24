import Combine
import Foundation
import QuartzCore
import SwiftUI
import UIKit

nonisolated struct PlayerSeekPreviewContext: Hashable, Sendable {
    let bvid: String
    let cid: Int

    init?(bvid: String, cid: Int?) {
        let normalizedBVID = bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBVID.isEmpty, let cid, cid > 0 else { return nil }
        self.bvid = normalizedBVID
        self.cid = cid
    }
}

nonisolated struct VideoShotTile: Hashable, Sendable {
    let sourceURL: URL
    let frameIndex: Int
    let column: Int
    let row: Int
    let columnCount: Int
    let rowCount: Int
}

nonisolated struct VideoShotMetadata: Decodable, Equatable, Sendable {
    let imageColumnCount: Int
    let imageRowCount: Int
    let imageColumnSize: Double
    let imageRowSize: Double
    let imageURLs: [String]
    let index: [Int]

    init(
        imageColumnCount: Int,
        imageRowCount: Int,
        imageColumnSize: Double,
        imageRowSize: Double,
        imageURLs: [String],
        index: [Int]
    ) {
        self.imageColumnCount = imageColumnCount
        self.imageRowCount = imageRowCount
        self.imageColumnSize = imageColumnSize
        self.imageRowSize = imageRowSize
        self.imageURLs = imageURLs
        self.index = index
    }

    enum CodingKeys: String, CodingKey {
        case imageColumnCount = "img_x_len"
        case imageRowCount = "img_y_len"
        case imageColumnSize = "img_x_size"
        case imageRowSize = "img_y_size"
        case imageURLs = "image"
        case index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageColumnCount = try container.decodeIfPresent(Int.self, forKey: .imageColumnCount) ?? 0
        imageRowCount = try container.decodeIfPresent(Int.self, forKey: .imageRowCount) ?? 0
        imageColumnSize = try container.decodeIfPresent(Double.self, forKey: .imageColumnSize) ?? 0
        imageRowSize = try container.decodeIfPresent(Double.self, forKey: .imageRowSize) ?? 0
        imageURLs = try container.decodeIfPresent([String].self, forKey: .imageURLs) ?? []
        index = try container.decodeIfPresent([Int].self, forKey: .index) ?? []
    }

    var isUsable: Bool {
        imageColumnCount > 0
            && imageRowCount > 0
            && !imageURLs.isEmpty
            && !index.isEmpty
    }

    var previewAspectRatio: CGFloat? {
        guard imageColumnSize > 0, imageRowSize > 0 else { return nil }
        return CGFloat(imageColumnSize / imageRowSize)
    }

    func tile(for seconds: TimeInterval) -> VideoShotTile? {
        guard isUsable else { return nil }
        let matchedIndexCount = index.lazy.filter { TimeInterval($0) <= seconds }.count
        let requestedFrame = max(0, matchedIndexCount - 2)
        let framesPerImage = imageColumnCount * imageRowCount
        guard framesPerImage > 0 else { return nil }
        let maximumFrame = imageURLs.count * framesPerImage - 1
        let frameIndex = min(max(requestedFrame, 0), maximumFrame)
        let imageIndex = frameIndex / framesPerImage
        guard imageURLs.indices.contains(imageIndex) else { return nil }
        let imageURLString = imageURLs[imageIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .normalizedBiliURL()
        guard let sourceURL = URL(string: imageURLString) else { return nil }
        let frameInImage = frameIndex % framesPerImage
        return VideoShotTile(
            sourceURL: sourceURL,
            frameIndex: frameIndex,
            column: frameInImage % imageColumnCount,
            row: frameInImage / imageColumnCount,
            columnCount: imageColumnCount,
            rowCount: imageRowCount
        )
    }
}

struct PlayerSeekPreviewPresentation {
    let progress: Double
    let duration: TimeInterval
    let image: UIImage?
    let imageAspectRatio: CGFloat?
    let isLoading: Bool
    let isCancelPending: Bool

    var currentTime: TimeInterval {
        min(max(progress, 0), 1) * duration
    }
}

@MainActor
final class PlayerSeekPreviewModel: ObservableObject {
    @Published private(set) var presentation: PlayerSeekPreviewPresentation?

    private enum MetadataState {
        case idle
        case waiting
        case loading
        case ready(VideoShotMetadata)
        case unavailable
    }

    private let metadataDelayNanoseconds: UInt64 = 120_000_000
    private let maximumCachedFrames = 16
    private var metadataState: MetadataState = .idle
    private var metadataContext: PlayerSeekPreviewContext?
    private var activeContext: PlayerSeekPreviewContext?
    private var activeSource: PlayerScrubInteractionSource?
    private var activeTile: VideoShotTile?
    private var activeImage: UIImage?
    private var frameCache = [VideoShotTile: UIImage]()
    private var frameCacheOrder = [VideoShotTile]()
    private var metadataLoadTask: Task<Void, Never>?
    private var imageLoadTask: Task<Void, Never>?
    private var metadataLoadGeneration = 0
    private var imageLoadGeneration = 0

    deinit {
        metadataLoadTask?.cancel()
        imageLoadTask?.cancel()
    }

    func beginScrub(
        api: BiliAPIClient?,
        context: PlayerSeekPreviewContext?,
        source: PlayerScrubInteractionSource,
        progress: Double,
        duration: TimeInterval
    ) {
        guard duration > 0 else {
            endScrub()
            return
        }
        activeContext = context
        activeSource = source
        activeTile = nil
        activeImage = nil
        publish(progress: progress, duration: duration, isCancelPending: false)

        guard let context, let api else { return }
        prepareMetadataIfNeeded(api: api, context: context)
    }

    func updateScrub(progress: Double, duration: TimeInterval) {
        guard duration > 0, let presentation else { return }
        publish(
            progress: progress,
            duration: duration,
            isCancelPending: presentation.isCancelPending
        )
        updateFrameIfPossible()
    }

    func setCancellationPending(_ isPending: Bool) {
        guard let presentation else { return }
        publish(
            progress: presentation.progress,
            duration: presentation.duration,
            isCancelPending: isPending
        )
    }

    func endScrub() {
        if case .waiting = metadataState {
            metadataLoadGeneration &+= 1
            metadataLoadTask?.cancel()
            metadataLoadTask = nil
            metadataState = .idle
        }
        presentation = nil
        activeContext = nil
        activeSource = nil
        activeTile = nil
        activeImage = nil
        imageLoadGeneration &+= 1
        imageLoadTask?.cancel()
        imageLoadTask = nil
    }

    private func prepareMetadataIfNeeded(api: BiliAPIClient, context: PlayerSeekPreviewContext) {
        if metadataContext != context {
            metadataLoadGeneration &+= 1
            metadataLoadTask?.cancel()
            imageLoadGeneration &+= 1
            imageLoadTask?.cancel()
            metadataLoadTask = nil
            imageLoadTask = nil
            metadataContext = context
            metadataState = .idle
            frameCache.removeAll()
            frameCacheOrder.removeAll()
        }

        switch metadataState {
        case .ready:
            updateFrameIfPossible()
        case .waiting, .loading, .unavailable:
            break
        case .idle:
            scheduleMetadataLoad(api: api, context: context)
        }
    }

    private func scheduleMetadataLoad(api: BiliAPIClient, context: PlayerSeekPreviewContext) {
        metadataLoadGeneration &+= 1
        let generation = metadataLoadGeneration
        metadataState = .waiting
        record("preview source=\(activeSource?.rawValue ?? "-") state=waiting")
        metadataLoadTask = Task { @MainActor [weak self, api, context] in
            do {
                try await Task.sleep(nanoseconds: self?.metadataDelayNanoseconds ?? 0)
                guard let self,
                      !Task.isCancelled,
                      self.metadataLoadGeneration == generation,
                      self.metadataContext == context,
                      self.activeContext == context,
                      self.presentation != nil
                else { return }

                self.metadataState = .loading
                self.refreshPresentation()
                self.record("preview state=metadataLoading")
                let metadata = try await api.fetchVideoShot(bvid: context.bvid, cid: context.cid)
                guard !Task.isCancelled,
                      self.metadataLoadGeneration == generation,
                      self.metadataContext == context
                else { return }

                self.metadataLoadTask = nil
                guard metadata.isUsable else {
                    self.metadataState = .unavailable
                    self.refreshPresentation()
                    self.record("preview state=unavailable reason=emptyMetadata")
                    return
                }
                self.metadataState = .ready(metadata)
                self.refreshPresentation()
                self.record("preview state=metadataReady sprites=\(metadata.imageURLs.count)")
                self.updateFrameIfPossible()
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.metadataLoadGeneration == generation,
                      self.metadataContext == context
                else { return }
                self.metadataLoadTask = nil
                self.metadataState = .unavailable
                self.refreshPresentation()
                self.record("preview state=unavailable reason=metadataRequest")
            }
        }
    }

    private func updateFrameIfPossible() {
        guard let presentation,
              let activeContext,
              activeContext == metadataContext,
              case .ready(let metadata) = metadataState,
              let tile = metadata.tile(for: presentation.currentTime)
        else { return }

        guard activeTile != tile else { return }
        activeTile = tile
        if let cached = frameCache[tile] {
            activeImage = cached
            refreshPresentation()
            return
        }

        activeImage = nil
        refreshPresentation()
        loadFrame(tile, metadata: metadata, context: activeContext)
    }

    private func loadFrame(
        _ tile: VideoShotTile,
        metadata: VideoShotMetadata,
        context: PlayerSeekPreviewContext
    ) {
        imageLoadGeneration &+= 1
        let generation = imageLoadGeneration
        imageLoadTask?.cancel()
        imageLoadTask = Task { @MainActor [weak self, tile, metadata, context] in
            let sprite = await RemoteImageCache.shared.load(
                url: tile.sourceURL,
                scale: 1,
                targetPixelSize: nil,
                priority: .visible
            )
            guard let self,
                  !Task.isCancelled,
                  self.imageLoadGeneration == generation,
                  self.activeContext == context,
                  self.activeTile == tile
            else { return }
            self.imageLoadTask = nil
            guard let sprite,
                  let frame = PlayerSeekPreviewImageCropper.crop(sprite: sprite, tile: tile)
            else {
                self.refreshPresentation()
                self.record("preview state=frameUnavailable")
                return
            }
            self.cache(frame, for: tile)
            self.activeImage = frame
            self.refreshPresentation()
            self.record("preview state=frameReady frame=\(tile.frameIndex) grid=\(metadata.imageColumnCount)x\(metadata.imageRowCount)")
        }
    }

    private func cache(_ image: UIImage, for tile: VideoShotTile) {
        frameCache[tile] = image
        frameCacheOrder.removeAll { $0 == tile }
        frameCacheOrder.append(tile)
        while frameCacheOrder.count > maximumCachedFrames {
            let removed = frameCacheOrder.removeFirst()
            frameCache[removed] = nil
        }
    }

    private func refreshPresentation() {
        guard let presentation else { return }
        publish(
            progress: presentation.progress,
            duration: presentation.duration,
            isCancelPending: presentation.isCancelPending
        )
    }

    private func publish(progress: Double, duration: TimeInterval, isCancelPending: Bool) {
        let metadata: VideoShotMetadata?
        if case .ready(let value) = metadataState {
            metadata = value
        } else {
            metadata = nil
        }
        let isLoading: Bool
        switch metadataState {
        case .loading:
            isLoading = true
        case .ready:
            isLoading = activeTile != nil && activeImage == nil && imageLoadTask != nil
        case .idle, .waiting, .unavailable:
            isLoading = false
        }
        presentation = PlayerSeekPreviewPresentation(
            progress: min(max(progress, 0), 1),
            duration: duration,
            image: activeImage,
            imageAspectRatio: metadata?.previewAspectRatio,
            isLoading: isLoading,
            isCancelPending: isCancelPending
        )
    }

    private func record(_ message: String) {
        guard let metricsID = activeContext?.bvid ?? metadataContext?.bvid,
              !metricsID.isEmpty
        else { return }
        PlayerMetricsLog.record(
            .seek,
            metricsID: metricsID,
            title: nil,
            message: message
        )
    }
}

private enum PlayerSeekPreviewImageCropper {
    static func crop(sprite: UIImage, tile: VideoShotTile) -> UIImage? {
        guard let source = sprite.cgImage,
              tile.columnCount > 0,
              tile.rowCount > 0
        else { return nil }
        let cellWidth = CGFloat(source.width) / CGFloat(tile.columnCount)
        let cellHeight = CGFloat(source.height) / CGFloat(tile.rowCount)
        guard cellWidth >= 1, cellHeight >= 1 else { return nil }
        let cropRect = CGRect(
            x: CGFloat(tile.column) * cellWidth,
            y: CGFloat(tile.row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        ).integral
        guard let cropped = source.cropping(to: cropRect) else { return nil }
        let image = UIImage(cgImage: cropped, scale: sprite.scale, orientation: .up)
        return image.preparingForDisplay() ?? image
    }
}
