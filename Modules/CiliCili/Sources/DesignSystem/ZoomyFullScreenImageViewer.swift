import Combine
import AVFoundation
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UIKit

nonisolated struct ZoomyViewerInitialImageLayout: Equatable {
    let contentSize: CGSize
    let usesLongImageScrolling: Bool
}

nonisolated enum ZoomyViewerImageQuality {
    static func shouldKeepCurrent(
        currentPixelSize: CGSize,
        candidatePixelSize: CGSize
    ) -> Bool {
        guard currentPixelSize.width > 0,
              currentPixelSize.height > 0,
              candidatePixelSize.width > 0,
              candidatePixelSize.height > 0
        else { return false }

        let currentAspectRatio = currentPixelSize.width / currentPixelSize.height
        let candidateAspectRatio = candidatePixelSize.width / candidatePixelSize.height
        let aspectRatioDifference = abs(currentAspectRatio - candidateAspectRatio)
            / max(currentAspectRatio, candidateAspectRatio)
        guard aspectRatioDifference < 0.04 else { return false }

        let currentPixelCount = currentPixelSize.width * currentPixelSize.height
        let candidatePixelCount = candidatePixelSize.width * candidatePixelSize.height
        return currentPixelCount > candidatePixelCount * 1.01
    }
}

nonisolated enum ZoomyViewerDismissGesturePolicy {
    static func isDownwardVerticalPull(_ translation: CGSize) -> Bool {
        translation.height > 0 && translation.height > abs(translation.width) * 1.15
    }

    static func shouldDismiss(translationY: CGFloat, velocityY: CGFloat) -> Bool {
        let translationY = max(translationY, 0)
        let projectedTranslationY = translationY + max(velocityY, 0) * 0.18
        return translationY > 120 || projectedTranslationY > 220
    }
}

nonisolated enum ZoomyViewerImageSizing {
    static let longImageHeightToWidthThreshold: CGFloat = 2.6
    private static let maximumDecodedPixelCount: CGFloat = 12_000_000
    private static let preferredDecodedWidth: CGFloat = 1_200
    private static let maximumDecodedDimension: CGFloat = 16_000

    static func usesLongImageScrolling(widthToHeightAspectRatio: CGFloat?) -> Bool {
        guard let widthToHeightAspectRatio, widthToHeightAspectRatio > 0 else { return false }
        return 1 / widthToHeightAspectRatio > longImageHeightToWidthThreshold
    }

    static func initialLayout(imageSize: CGSize, boundsSize: CGSize) -> ZoomyViewerInitialImageLayout {
        guard imageSize.width > 0,
              imageSize.height > 0,
              boundsSize.width > 0,
              boundsSize.height > 0
        else {
            return ZoomyViewerInitialImageLayout(contentSize: .zero, usesLongImageScrolling: false)
        }

        let heightToWidthRatio = imageSize.height / imageSize.width
        let widthFittedHeight = boundsSize.width * heightToWidthRatio
        if heightToWidthRatio > longImageHeightToWidthThreshold,
           widthFittedHeight > boundsSize.height {
            return ZoomyViewerInitialImageLayout(
                contentSize: CGSize(width: boundsSize.width, height: widthFittedHeight),
                usesLongImageScrolling: true
            )
        }

        let scale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
        return ZoomyViewerInitialImageLayout(
            contentSize: CGSize(width: imageSize.width * scale, height: imageSize.height * scale),
            usesLongImageScrolling: false
        )
    }

    static func targetPixelSize(
        baseTargetPixelSize: Int,
        widthToHeightAspectRatio: CGFloat?
    ) -> Int {
        let baseTargetPixelSize = max(baseTargetPixelSize, 1)
        guard usesLongImageScrolling(widthToHeightAspectRatio: widthToHeightAspectRatio),
              let widthToHeightAspectRatio
        else { return baseTargetPixelSize }

        let heightToWidthRatio = 1 / widthToHeightAspectRatio
        let budgetedWidth = sqrt(maximumDecodedPixelCount / heightToWidthRatio)
        let decodedWidth = min(preferredDecodedWidth, budgetedWidth)
        let decodedHeight = min(maximumDecodedDimension, decodedWidth * heightToWidthRatio)
        return max(baseTargetPixelSize, Int(decodedHeight.rounded(.up)))
    }
}

struct ZoomyFullScreenImageViewer: View {
    @Environment(\.colorScheme) private var colorScheme
    let initialImage: UIImage?
    let url: URL?
    let items: [ZoomyImagePreviewItem]
    let initialItemID: String
    let viewerGroup: ZoomyImagePreviewGroup?
    let targetPixelSize: Int
    let onSelectedItemChanged: (ZoomyImagePreviewItem, UIImage?) -> Void
    let onDismissDragChanged: (CGFloat, CGFloat) -> Void
    let onImageUpdated: (UIImage) -> Void
    @Binding var isPresented: Bool
    @State private var selectedItemID: String
    @State private var dismissDragOffset: CGFloat = 0
    @State private var dismissGestureItemID: String?
    @State private var selectedSnapshot: ZoomyViewerMediaSnapshot?
    @State private var isSavingImage = false
    @State private var isPreparingShare = false
    @State private var sharePayload: ZoomySharePayload?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    init(
        initialImage: UIImage?,
        url: URL?,
        items: [ZoomyImagePreviewItem],
        initialItemID: String,
        viewerGroup: ZoomyImagePreviewGroup?,
        targetPixelSize: Int,
        isPresented: Binding<Bool>,
        onSelectedItemChanged: @escaping (ZoomyImagePreviewItem, UIImage?) -> Void,
        onDismissDragChanged: @escaping (CGFloat, CGFloat) -> Void,
        onImageUpdated: @escaping (UIImage) -> Void
    ) {
        self.initialImage = initialImage
        self.url = url
        self.items = items
        self.initialItemID = initialItemID
        self.viewerGroup = viewerGroup
        self.targetPixelSize = targetPixelSize
        self.onSelectedItemChanged = onSelectedItemChanged
        self.onDismissDragChanged = onDismissDragChanged
        self.onImageUpdated = onImageUpdated
        _isPresented = isPresented
        _selectedItemID = State(initialValue: initialItemID)
    }

    var body: some View {
        viewerSurface
            .onAppear {
                syncSelectedItemContext()
                prewarmNeighborImages()
            }
            .onChange(of: selectedItemID) { _, newItemID in
                if let dismissGestureItemID, newItemID != dismissGestureItemID {
                    selectedItemID = dismissGestureItemID
                    return
                }
                syncSelectedItemContext()
                prewarmNeighborImages()
            }
            .sheet(item: $sharePayload) { payload in
                ZoomyActivityView(activityItems: payload.activityItems)
            }
            .onDisappear {
                toastTask?.cancel()
            }
            .statusBarHidden(true)
            .accessibilityLabel("图片预览")
    }

    private var viewerSurface: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            ZStack {
                if items.count > 1 {
                    TabView(selection: $selectedItemID) {
                        ForEach(items) { item in
                            imagePage(for: item)
                                .tag(item.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                } else {
                    imagePage(for: items.first)
                        .ignoresSafeArea()
                }

                pageIndicator
            }
            .offset(y: dismissDragOffset)
        }
    }

    private var backgroundOpacity: Double {
        let progress = min(max(abs(dismissDragOffset) / 260, 0), 1)
        return 1 - progress * 0.45
    }

    @ViewBuilder
    private var pageIndicator: some View {
        VStack {
            Spacer()
            viewerActionBar
                .padding(.bottom, 22)
                .opacity(pageIndicatorOpacity)

            if let toastMessage {
                Text(toastMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(.black.opacity(0.58), in: Capsule())
                    .padding(.bottom, 10)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var viewerActionContent: some View {
        HStack(spacing: 18) {
            viewerActionButton(systemImage: "square.and.arrow.down", accessibilityLabel: "保存图片") {
                saveCurrentImage()
            }
            .disabled(!canExportSelectedMedia || isSavingImage || isPreparingShare)

            if items.count > 1 {
                ZoomyViewerPageControl(numberOfPages: items.count, currentPage: selectedIndex)
                    .frame(width: min(CGFloat(items.count) * 18 + 24, 180), height: 22)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            viewerActionButton(systemImage: "square.and.arrow.up", accessibilityLabel: "分享图片") {
                shareCurrentImage()
            }
            .disabled(!canExportSelectedMedia || isSavingImage || isPreparingShare)
        }
    }

    private var viewerActionBar: some View {
        viewerActionContent
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .biliGlassEffect(interactive: true, in: Capsule())
    }

    private func viewerActionButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
    }

    private var pageIndicatorOpacity: Double {
        let progress = min(max(abs(dismissDragOffset) / 180, 0), 1)
        return 1 - progress
    }

    @ViewBuilder
    private func imagePage(for item: ZoomyImagePreviewItem?) -> some View {
        if let item {
            ZoomyViewerImagePage(
                item: item,
                initialImage: initialImage(for: item),
                targetPixelSize: targetPixelSize,
                isSelected: item.id == selectedItemID,
                isPresented: $isPresented,
                onDismissDragChanged: updateDismissDrag,
                onDismissDragEnded: finishDismissDrag,
                onMediaUpdated: { itemID, snapshot in
                    if let image = snapshot.image {
                        viewerGroup?.setImage(image, for: itemID, quality: .viewer)
                    }
                    if itemID == selectedItemID {
                        updateSelectedMedia(itemID: itemID, snapshot: snapshot)
                    }
                }
            )
        } else if let url {
            ZoomyViewerImagePage(
                item: ZoomyImagePreviewItem(id: url.absoluteString, viewerURL: url),
                initialImage: initialImage,
                targetPixelSize: targetPixelSize,
                isSelected: true,
                isPresented: $isPresented,
                onDismissDragChanged: updateDismissDrag,
                onDismissDragEnded: finishDismissDrag,
                onMediaUpdated: { _, snapshot in
                    selectedSnapshot = snapshot
                    if let image = snapshot.image {
                        onImageUpdated(image)
                    }
                }
            )
        } else {
            ProgressView()
                .tint(.primary)
        }
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selectedItemID } ?? 0
    }

    private var selectedItem: ZoomyImagePreviewItem {
        let item = items.indices.contains(selectedIndex) ? items[selectedIndex] : items.first
        return item ?? ZoomyImagePreviewItem(
            id: url?.absoluteString ?? initialItemID,
            viewerURL: url
        )
    }

    private var canExportSelectedMedia: Bool {
        if selectedItem.needsOriginalMedia {
            return selectedSnapshot?.isFinal == true
        }
        return selectedItem.displayURL != nil || selectedSnapshot?.isFinal == true
    }

    private func item(withID id: String) -> ZoomyImagePreviewItem? {
        items.first { $0.id == id }
    }

    private func initialImage(for item: ZoomyImagePreviewItem) -> UIImage? {
        if item.id == initialItemID {
            return initialImage ?? viewerGroup?.image(for: item.id)
        }
        return viewerGroup?.image(for: item.id)
    }

    private func updateDismissDrag(itemID: String, translationY: CGFloat) {
        guard itemID == selectedItemID else { return }
        if dismissGestureItemID == nil {
            dismissGestureItemID = itemID
        }
        guard dismissGestureItemID == itemID else { return }
        let translationY = max(translationY, 0)
        dismissDragOffset = translationY
        onDismissDragChanged(translationY, 1)
    }

    private func finishDismissDrag(
        itemID: String,
        translationY: CGFloat,
        velocityY: CGFloat,
        cancelled: Bool
    ) {
        guard dismissGestureItemID == itemID else {
            resetDismissDrag()
            return
        }
        dismissGestureItemID = nil
        let translationY = max(translationY, 0)
        if !cancelled,
           ZoomyViewerDismissGesturePolicy.shouldDismiss(
               translationY: translationY,
               velocityY: velocityY
           ) {
            onDismissDragChanged(translationY, 1)
            isPresented = false
            return
        }
        resetDismissDrag()
    }

    private func resetDismissDrag() {
        dismissGestureItemID = nil
        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
            dismissDragOffset = 0
            onDismissDragChanged(0, 1)
        }
    }

    private func syncSelectedItemContext() {
        guard let item = items.first(where: { $0.id == selectedItemID }) else { return }
        viewerGroup?.releaseViewerImages(except: item.id)
        let cachedImage = viewerGroup?.image(for: item.id)
        onSelectedItemChanged(item, cachedImage)
        selectedSnapshot = item.needsOriginalMedia
            ? nil
            : cachedImage.map { ZoomyViewerMediaSnapshot(image: $0, isFinal: false) }
        if let cachedImage {
            onImageUpdated(cachedImage)
        }
    }

    private func prewarmNeighborImages() {
        guard items.count > 1 else { return }
        let neighborIndices = [selectedIndex - 1, selectedIndex + 1]
        let neighborItems = neighborIndices.compactMap { index -> ZoomyImagePreviewItem? in
            guard items.indices.contains(index),
                  !items[index].needsOriginalMedia,
                  items[index].displayURL != nil
            else { return nil }
            return items[index]
        }
        guard !neighborItems.isEmpty else { return }
        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for item in neighborItems {
                    guard let url = item.displayURL else { continue }
                    let prewarmTargetPixelSize = ZoomyViewerImageSizing.targetPixelSize(
                        baseTargetPixelSize: targetPixelSize,
                        widthToHeightAspectRatio: item.resolvedAspectRatio
                    )
                    group.addTask {
                        await RemoteImageCache.shared.prefetch(
                            [RemoteImageSource(url: url)],
                            targetPixelSize: prewarmTargetPixelSize,
                            maximumConcurrentLoads: 1,
                            decodePolicy: .highQualityViewer
                        )
                    }
                }
            }
        }
    }

    func cancelLoading() {
    }

    private func updateSelectedMedia(itemID: String, snapshot: ZoomyViewerMediaSnapshot) {
        guard itemID == selectedItemID else { return }
        selectedSnapshot = snapshot
        if let image = snapshot.image {
            onImageUpdated(image)
        }
    }

    private func saveCurrentImage() {
        guard canExportSelectedMedia else { return }
        guard !isSavingImage else { return }
        let item = selectedItem
        let snapshot = selectedSnapshot
        isSavingImage = true
        showToast("正在准备原图")
        Task { @MainActor in
            guard let exportSnapshot = await ZoomyViewerMediaLoader.exportSnapshot(
                snapshot,
                for: item
            ) else {
                isSavingImage = false
                showToast("原图加载失败")
                return
            }
            if item.id == selectedItemID {
                selectedSnapshot = exportSnapshot
            }
            let didSave = await ZoomyPhotoLibrarySaver.save(exportSnapshot)
            isSavingImage = false
            if didSave {
                Haptics.success()
                showToast("已保存到照片")
            } else {
                showToast("保存失败")
            }
        }
    }

    private func shareCurrentImage() {
        guard canExportSelectedMedia, !isPreparingShare else { return }
        let item = selectedItem
        let snapshot = selectedSnapshot
        isPreparingShare = true
        showToast("正在准备原图")
        Task { @MainActor in
            guard let exportSnapshot = await ZoomyViewerMediaLoader.exportSnapshot(
                snapshot,
                for: item
            ) else {
                isPreparingShare = false
                showToast("原图加载失败")
                return
            }
            if item.id == selectedItemID {
                selectedSnapshot = exportSnapshot
            }
            let items = ZoomyShareItemBuilder.activityItems(
                snapshot: exportSnapshot,
                item: item
            )
            isPreparingShare = false
            guard !items.isEmpty else {
                showToast("分享准备失败")
                return
            }
            Haptics.light()
            sharePayload = ZoomySharePayload(activityItems: items)
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.18)) {
            toastMessage = message
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.18)) {
                toastMessage = nil
            }
        }
    }
}

private struct ZoomyViewerImagePage: View {
    let item: ZoomyImagePreviewItem
    let initialImage: UIImage?
    let targetPixelSize: Int
    let isSelected: Bool
    @Binding var isPresented: Bool
    let onDismissDragChanged: (String, CGFloat) -> Void
    let onDismissDragEnded: (String, CGFloat, CGFloat, Bool) -> Void
    let onMediaUpdated: (String, ZoomyViewerMediaSnapshot) -> Void
    @StateObject private var loader: ZoomyViewerImageLoader
    @State private var retryRequestID = 0

    init(
        item: ZoomyImagePreviewItem,
        initialImage: UIImage?,
        targetPixelSize: Int,
        isSelected: Bool,
        isPresented: Binding<Bool>,
        onDismissDragChanged: @escaping (String, CGFloat) -> Void,
        onDismissDragEnded: @escaping (String, CGFloat, CGFloat, Bool) -> Void,
        onMediaUpdated: @escaping (String, ZoomyViewerMediaSnapshot) -> Void
    ) {
        self.item = item
        self.initialImage = initialImage
        self.targetPixelSize = targetPixelSize
        self.isSelected = isSelected
        _isPresented = isPresented
        self.onDismissDragChanged = onDismissDragChanged
        self.onDismissDragEnded = onDismissDragEnded
        self.onMediaUpdated = onMediaUpdated
        _loader = StateObject(wrappedValue: ZoomyViewerImageLoader(initialImage: initialImage))
    }

    var body: some View {
        ZStack {
            if let livePhoto = loader.snapshot?.livePhoto,
               let image = loader.snapshot?.image {
                ZoomyLivePhotoView(
                    livePhoto: livePhoto,
                    placeholderImage: image,
                    isDismissGestureEnabled: isSelected
                ) {
                    isPresented = false
                } onDismissDragChanged: { translationY in
                    onDismissDragChanged(item.id, translationY)
                } onDismissDragEnded: { translationY, velocityY, cancelled in
                    onDismissDragEnded(item.id, translationY, velocityY, cancelled)
                }
                .ignoresSafeArea()
                .onAppear {
                    reportSnapshotIfNeeded()
                }
            } else if let liveVideoURL = loader.snapshot?.liveVideoFileURL,
                      let image = loader.snapshot?.image {
                ZoomyLiveVideoView(
                    videoURL: liveVideoURL,
                    placeholderImage: image,
                    isDismissGestureEnabled: isSelected
                ) {
                    isPresented = false
                } onDismissDragChanged: { translationY in
                    onDismissDragChanged(item.id, translationY)
                } onDismissDragEnded: { translationY, velocityY, cancelled in
                    onDismissDragEnded(item.id, translationY, velocityY, cancelled)
                }
                .ignoresSafeArea()
                .onAppear {
                    reportSnapshotIfNeeded()
                }
            } else if let image = loader.snapshot?.image {
                ZoomyZoomableImageView(
                    image: image,
                    isDismissGestureEnabled: isSelected
                ) {
                    isPresented = false
                } onDismissDragChanged: { translationY in
                    onDismissDragChanged(item.id, translationY)
                } onDismissDragEnded: { translationY, velocityY, cancelled in
                    onDismissDragEnded(item.id, translationY, velocityY, cancelled)
                }
                .ignoresSafeArea()
                .onAppear {
                    reportSnapshotIfNeeded()
                }
            } else if loader.loadFailed {
                failureIndicator
            } else {
                loadingIndicator
            }

            if loader.isLoadingFinalMedia, loader.snapshot?.image != nil {
                compactLoadingIndicator
            } else if loader.loadFailed, loader.snapshot?.image != nil {
                compactRetryButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(item.displayURL?.absoluteString ?? item.id)|\(isSelected)|\(retryRequestID)") {
            guard isSelected, isPresented else {
                loader.cancel()
                return
            }
            await loader.load(
                item: item,
                targetPixelSize: effectiveTargetPixelSize
            )
        }
        .onAppear {
            reportSnapshotIfNeeded()
        }
        .onChange(of: loader.snapshotVersion) { _, _ in
            reportSnapshotIfNeeded()
        }
        .onChange(of: isPresented) { _, isPresented in
            if !isPresented {
                loader.cancel()
            }
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var effectiveTargetPixelSize: Int {
        let initialAspectRatio: CGFloat? = initialImage.flatMap { image in
            guard image.size.width > 0, image.size.height > 0 else { return nil }
            return image.size.width / image.size.height
        }
        return ZoomyViewerImageSizing.targetPixelSize(
            baseTargetPixelSize: targetPixelSize,
            widthToHeightAspectRatio: item.resolvedAspectRatio ?? initialAspectRatio
        )
    }

    private func reportSnapshotIfNeeded() {
        guard let snapshot = loader.snapshot else { return }
        if item.needsOriginalMedia, !snapshot.isFinal {
            return
        }
        onMediaUpdated(item.id, snapshot)
    }

    private var loadingIndicator: some View {
        GlassEffectContainer(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(.white)
                .frame(width: 76, height: 76)
                .videoCoverBadgeForeground(opacity: 0)
                .videoCoverBadgeBackground(style: .clear, in: Circle())
                .allowsHitTesting(false)
                .accessibilityLabel("正在加载原图")
        }
    }

    private var compactLoadingIndicator: some View {
        VStack {
            HStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(width: 38, height: 38)
                    .videoCoverBadgeForeground(opacity: 0)
                    .videoCoverBadgeBackground(style: .clear, in: Circle())
                    .allowsHitTesting(false)
                    .accessibilityLabel("正在加载原图")
            }
            Spacer()
        }
        .padding(.top, 18)
        .padding(.trailing, 16)
    }

    private var compactRetryButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: retryLoading) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .biliLiquidGlassForeground(shadowOpacity: 0.34)
                .biliGlassEffect(tint: .black.opacity(0.24), interactive: true, in: Circle())
                .accessibilityLabel("重新加载原图")
            }
            Spacer()
        }
        .padding(.top, 18)
        .padding(.trailing, 16)
    }

    private var failureIndicator: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 30, weight: .medium))

            Text("图片加载失败")
                .font(.subheadline.weight(.semibold))

            Button(action: retryLoading) {
                Label("重新加载", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .biliLiquidGlassForeground(shadowOpacity: 0.34)
            .biliGlassEffect(tint: .black.opacity(0.24), interactive: true, in: Capsule())
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
    }

    private func retryLoading() {
        loader.prepareForRetry()
        retryRequestID &+= 1
    }
}

@MainActor
private final class ZoomyViewerImageLoader: ObservableObject {
    @Published private(set) var snapshot: ZoomyViewerMediaSnapshot?
    @Published private(set) var snapshotVersion = 0
    @Published private(set) var isLoadingFinalMedia = false
    @Published private(set) var loadFailed = false
    private var task: Task<Void, Never>?
    private var loadGeneration = 0
    private var finalLoadIdentity: String?

    init(initialImage: UIImage?) {
        snapshot = initialImage.map { ZoomyViewerMediaSnapshot(image: $0, isFinal: false) }
    }

    func load(
        item: ZoomyImagePreviewItem,
        targetPixelSize: Int
    ) async {
        cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        let url = item.displayURL
        guard let url else {
            isLoadingFinalMedia = false
            loadFailed = true
            return
        }
        let loadIdentity = "\(url.absoluteString)|\(targetPixelSize)"
        if finalLoadIdentity == loadIdentity, snapshot?.isFinal == true {
            isLoadingFinalMedia = false
            loadFailed = false
            return
        }
        isLoadingFinalMedia = true
        loadFailed = false
        task = Task(priority: .userInitiated) { [weak self] in
            let snapshot: ZoomyViewerMediaSnapshot?
            if item.isLiveImage, let liveVideoURL = item.liveVideoURL {
                snapshot = await ZoomyViewerMediaLoader.loadLivePhoto(
                    imageURL: url,
                    videoURL: liveVideoURL,
                    targetPixelSize: targetPixelSize
                )
            } else if item.isAnimatedGIF {
                snapshot = await ZoomyViewerMediaLoader.loadAnimatedGIF(
                    url: url,
                    targetPixelSize: targetPixelSize
                )
            } else {
                snapshot = await ZoomyViewerMediaLoader.loadStaticImage(
                    url: url,
                    targetPixelSize: targetPixelSize,
                    decodePolicy: .highQualityViewer
                )
            }

            guard !Task.isCancelled else { return }
            if let snapshot {
                await MainActor.run {
                    guard self?.loadGeneration == generation else { return }
                    self?.setSnapshot(snapshot, loadIdentity: loadIdentity)
                }
                return
            }

            let fallbackImage = await RemoteImageCache.shared.load(
                url: url,
                scale: 1,
                targetPixelSize: targetPixelSize,
                decodePolicy: .highQualityViewer
            )
            guard !Task.isCancelled else { return }
            guard let fallbackImage else {
                await MainActor.run {
                    guard self?.loadGeneration == generation else { return }
                    self?.isLoadingFinalMedia = false
                    self?.loadFailed = true
                }
                return
            }
            await MainActor.run {
                guard self?.loadGeneration == generation else { return }
                self?.setSnapshot(
                    ZoomyViewerMediaSnapshot(image: fallbackImage, isFinal: true),
                    loadIdentity: loadIdentity
                )
            }
        }
        await task?.value
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoadingFinalMedia = false
    }

    func prepareForRetry() {
        cancel()
        loadFailed = false
    }

    private func setSnapshot(_ snapshot: ZoomyViewerMediaSnapshot, loadIdentity: String) {
        let resolvedSnapshot = snapshot.preservingSharperDisplayImage(from: self.snapshot)
        self.snapshot = resolvedSnapshot
        snapshotVersion += 1
        loadFailed = false
        if resolvedSnapshot.isFinal {
            finalLoadIdentity = loadIdentity
            isLoadingFinalMedia = false
        }
    }
}

private struct ZoomyViewerMediaSnapshot {
    let image: UIImage?
    let imageFileURL: URL?
    let liveVideoFileURL: URL?
    let livePhoto: PHLivePhoto?
    let isAnimatedGIF: Bool
    let isLivePhoto: Bool
    let isFinal: Bool

    init(
        image: UIImage?,
        imageFileURL: URL? = nil,
        liveVideoFileURL: URL? = nil,
        livePhoto: PHLivePhoto? = nil,
        isAnimatedGIF: Bool = false,
        isLivePhoto: Bool = false,
        isFinal: Bool = true
    ) {
        self.image = image
        self.imageFileURL = imageFileURL
        self.liveVideoFileURL = liveVideoFileURL
        self.livePhoto = livePhoto
        self.isAnimatedGIF = isAnimatedGIF
        self.isLivePhoto = isLivePhoto || liveVideoFileURL != nil
        self.isFinal = isFinal
    }

    func replacingImageFileURL(_ imageFileURL: URL) -> Self {
        Self(
            image: image,
            imageFileURL: imageFileURL,
            liveVideoFileURL: liveVideoFileURL,
            livePhoto: livePhoto,
            isAnimatedGIF: isAnimatedGIF,
            isLivePhoto: isLivePhoto,
            isFinal: true
        )
    }

    func preservingSharperDisplayImage(from current: Self?) -> Self {
        guard !isAnimatedGIF,
              !isLivePhoto,
              let currentImage = current?.image,
              let image,
              ZoomyViewerImageQuality.shouldKeepCurrent(
                  currentPixelSize: currentImage.zoomyPixelSize,
                  candidatePixelSize: image.zoomyPixelSize
              )
        else { return self }

        return Self(
            image: currentImage,
            imageFileURL: imageFileURL,
            liveVideoFileURL: liveVideoFileURL,
            livePhoto: livePhoto,
            isAnimatedGIF: isAnimatedGIF,
            isLivePhoto: isLivePhoto,
            isFinal: isFinal
        )
    }
}

private extension UIImage {
    var zoomyPixelSize: CGSize {
        if let cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private struct ZoomySharePayload: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

private struct ZoomyActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

private enum ZoomyShareItemBuilder {
    static func activityItems(
        snapshot: ZoomyViewerMediaSnapshot?,
        item: ZoomyImagePreviewItem
    ) -> [Any] {
        guard let snapshot else {
            return item.displayURL.map { [$0] } ?? []
        }

        if snapshot.isLivePhoto {
            let resources = [snapshot.imageFileURL, snapshot.liveVideoFileURL].compactMap(\.self)
            if !resources.isEmpty {
                return resources
            }
        }

        if snapshot.isAnimatedGIF {
            if let fileURL = snapshot.imageFileURL {
                return [fileURL]
            }
        }

        if let fileURL = snapshot.imageFileURL {
            return [fileURL]
        }

        if let image = snapshot.image {
            return [image]
        }
        return item.displayURL.map { [$0] } ?? []
    }
}

@MainActor
private enum ZoomyPhotoLibrarySaver {
    static func save(_ snapshot: ZoomyViewerMediaSnapshot) async -> Bool {
        guard await requestAddAuthorization() else { return false }

        if snapshot.isLivePhoto,
           let imageFileURL = snapshot.imageFileURL,
           let liveVideoFileURL = snapshot.liveVideoFileURL,
           await saveLivePhoto(imageFileURL: imageFileURL, videoFileURL: liveVideoFileURL) {
            return true
        }

        if snapshot.isAnimatedGIF {
            if let fileURL = snapshot.imageFileURL,
               await saveImageFile(fileURL) {
                return true
            }
        }

        if let fileURL = snapshot.imageFileURL,
           await saveImageFile(fileURL) {
            return true
        }

        if let image = snapshot.image {
            return await saveStaticImage(image)
        }
        return false
    }

    private static func requestAddAuthorization() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status)
                }
            }
            return status == .authorized || status == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func saveStaticImage(_ image: UIImage) async -> Bool {
        await performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    private static func saveImageFile(_ fileURL: URL) async -> Bool {
        await performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }
    }

    private static func saveLivePhoto(imageFileURL: URL, videoFileURL: URL) async -> Bool {
        await performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: imageFileURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: videoFileURL, options: nil)
        }
    }

    private static func performChanges(_ changes: @escaping () -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges(changes) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

struct ZoomyAnimatedImageDecodeBudget: Equatable {
    let maximumFrameCount: Int
    let maximumPixelSize: Int
    let maximumDecodedPixels: Int

    static func current(targetPixelSize: Int) -> Self {
        let processInfo = ProcessInfo.processInfo
        let isConstrained = processInfo.isLowPowerModeEnabled || isConstrained(processInfo.thermalState)
        return make(targetPixelSize: targetPixelSize, isConstrained: isConstrained)
    }

    static func make(targetPixelSize: Int, isConstrained: Bool) -> Self {
        let targetPixelSize = max(targetPixelSize, 1)
        if isConstrained {
            return Self(
                maximumFrameCount: 14,
                maximumPixelSize: min(targetPixelSize, 900),
                maximumDecodedPixels: 9_000_000
            )
        }
        return Self(
            maximumFrameCount: 24,
            maximumPixelSize: min(targetPixelSize, 1_280),
            maximumDecodedPixels: 18_000_000
        )
    }

    func sampledFrameIndices(frameCount: Int, maximumFrameCount: Int? = nil) -> [Int] {
        guard frameCount > 0 else { return [] }
        let selectedFrameCount = min(frameCount, max(maximumFrameCount ?? self.maximumFrameCount, 1))
        guard selectedFrameCount > 1 else { return [0] }
        guard selectedFrameCount < frameCount else { return Array(0..<frameCount) }

        return (0..<selectedFrameCount).map { index in
            index * (frameCount - 1) / (selectedFrameCount - 1)
        }
    }

    private static func isConstrained(_ thermalState: ProcessInfo.ThermalState) -> Bool {
        switch thermalState {
        case .serious, .critical:
            true
        case .nominal, .fair:
            false
        @unknown default:
            true
        }
    }
}

private enum ZoomyViewerMediaLoader {
    private static let temporaryDirectoryName = "ZoomyMedia"
    private static let maximumTemporaryFileAge: TimeInterval = 24 * 60 * 60
    private static let maximumTemporaryFileCount = 48
    private static let maximumTemporaryFileBytes = 160 * 1_024 * 1_024

    static func exportSnapshot(
        _ snapshot: ZoomyViewerMediaSnapshot?,
        for item: ZoomyImagePreviewItem
    ) async -> ZoomyViewerMediaSnapshot? {
        if item.needsOriginalMedia {
            guard let snapshot, snapshot.isFinal else { return nil }
            return snapshot
        }

        if let snapshot, snapshot.isFinal, snapshot.imageFileURL != nil {
            return snapshot
        }

        guard let url = item.displayURL else {
            return snapshot?.isFinal == true ? snapshot : nil
        }
        do {
            let fileURL = try await downloadTemporaryFile(
                from: url,
                acceptsVideo: false,
                fallbackExtension: "jpg"
            )
            if let snapshot {
                return snapshot.replacingImageFileURL(fileURL)
            }
            return ZoomyViewerMediaSnapshot(
                image: nil,
                imageFileURL: fileURL,
                isFinal: true
            )
        } catch {
            return nil
        }
    }

    static func loadStaticImage(
        url: URL,
        targetPixelSize: Int,
        decodePolicy: RemoteImageDecodePolicy = .standard
    ) async -> ZoomyViewerMediaSnapshot? {
        let initialImage: UIImage
        if let cachedImage = await RemoteImageCache.shared.image(
            for: url,
            scale: 1,
            targetPixelSize: targetPixelSize,
            decodePolicy: decodePolicy
        ) {
            initialImage = cachedImage
        } else {
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled,
                  let loadedImage = await RemoteImageCache.shared.load(
                      url: url,
                      scale: 1,
                      targetPixelSize: targetPixelSize,
                      decodePolicy: decodePolicy
                  )
            else { return nil }
            initialImage = loadedImage
        }

        let aspectRatio: CGFloat? = {
            guard initialImage.size.width > 0, initialImage.size.height > 0 else { return nil }
            return initialImage.size.width / initialImage.size.height
        }()
        let refinedTargetPixelSize = ZoomyViewerImageSizing.targetPixelSize(
            baseTargetPixelSize: targetPixelSize,
            widthToHeightAspectRatio: aspectRatio
        )
        guard refinedTargetPixelSize > targetPixelSize,
              !Task.isCancelled,
              let refinedImage = await RemoteImageCache.shared.load(
                  url: url,
                  scale: 1,
                  targetPixelSize: refinedTargetPixelSize,
                  decodePolicy: decodePolicy
              )
        else {
            return ZoomyViewerMediaSnapshot(image: initialImage, isFinal: true)
        }
        return ZoomyViewerMediaSnapshot(image: refinedImage, isFinal: true)
    }

    static func loadAnimatedGIF(url: URL, targetPixelSize: Int) async -> ZoomyViewerMediaSnapshot? {
        var fileURL: URL?
        do {
            let downloadedFileURL = try await downloadTemporaryFile(
                from: url,
                acceptsVideo: false,
                fallbackExtension: "gif"
            )
            fileURL = downloadedFileURL
            try Task.checkCancellation()
            guard let image = animatedGIFImage(fileURL: downloadedFileURL, targetPixelSize: targetPixelSize) else {
                throw URLError(.cannotDecodeContentData)
            }
            try Task.checkCancellation()
            return ZoomyViewerMediaSnapshot(
                image: image,
                imageFileURL: downloadedFileURL,
                isAnimatedGIF: true,
                isFinal: true
            )
        } catch {
            if let fileURL {
                removeTemporaryFile(fileURL)
            }
            return nil
        }
    }

    static func loadLivePhoto(
        imageURL: URL,
        videoURL: URL,
        targetPixelSize: Int
    ) async -> ZoomyViewerMediaSnapshot? {
        var imageFileURL: URL?
        var videoFileURL: URL?
        do {
            async let imageDownload = downloadTemporaryFile(
                from: imageURL,
                acceptsVideo: false,
                fallbackExtension: "jpg"
            )
            async let videoDownload = downloadTemporaryFile(
                from: videoURL,
                acceptsVideo: true,
                fallbackExtension: "mov"
            )
            imageFileURL = try await imageDownload
            videoFileURL = try await videoDownload
            try Task.checkCancellation()
            guard let imageFileURL,
                  let videoFileURL,
                  let image = downsampledImage(fileURL: imageFileURL, targetPixelSize: targetPixelSize)
            else {
                throw URLError(.cannotDecodeContentData)
            }
            let livePhoto = await requestLivePhoto(
                imageFileURL: imageFileURL,
                videoFileURL: videoFileURL,
                placeholderImage: image
            )
            try Task.checkCancellation()
            return ZoomyViewerMediaSnapshot(
                image: image,
                imageFileURL: imageFileURL,
                liveVideoFileURL: videoFileURL,
                livePhoto: livePhoto,
                isLivePhoto: true,
                isFinal: true
            )
        } catch {
            if let imageFileURL {
                removeTemporaryFile(imageFileURL)
            }
            if let videoFileURL {
                removeTemporaryFile(videoFileURL)
            }
            guard !Task.isCancelled else { return nil }
            return await loadStaticImage(url: imageURL, targetPixelSize: targetPixelSize)
        }
    }

    private static func downloadTemporaryFile(
        from url: URL,
        acceptsVideo: Bool,
        fallbackExtension: String
    ) async throws -> URL {
        var request = URLRequest(url: url)
        var headers = BiliURLSessionFactory.imageHeaders()
        if acceptsVideo {
            headers["Accept"] = "*/*"
        }
        headers.forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }

        let session = BiliURLSessionFactory.makeImageSession()
        defer { session.finishTasksAndInvalidate() }
        let (temporaryURL, response) = try await session.download(for: request)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()
        return try persistTemporaryFile(
            at: temporaryURL,
            originalURL: url,
            fallbackExtension: fallbackExtension
        )
    }

    private static func animatedGIFImage(fileURL: URL, targetPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            return downsampledImage(fileURL: fileURL, targetPixelSize: targetPixelSize)
        }

        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        let budget = ZoomyAnimatedImageDecodeBudget.current(targetPixelSize: targetPixelSize)
        let selectedFrameIndices = Set(
            budget.sampledFrameIndices(
                frameCount: frameCount,
                maximumFrameCount: maximumFrameCount(for: source, budget: budget)
            )
        )
        let maxPixelSize = effectiveThumbnailPixelSize(source: source, budget: budget)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        for index in 0..<frameCount {
            duration += gifFrameDuration(source: source, index: index)
            guard selectedFrameIndices.contains(index), !Task.isCancelled else { continue }
            let frame: UIImage? = autoreleasepool {
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                    return nil
                }
                return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
            }
            if let frame {
                frames.append(frame)
            }
        }

        guard !Task.isCancelled else { return nil }
        guard frames.count > 1 else { return frames.first }
        return UIImage.animatedImage(with: frames, duration: max(duration, Double(frames.count) * 0.08))
    }

    private static func gifFrameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.08 }
        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval
        return max(unclamped ?? clamped ?? 0.08, 0.02)
    }

    private static func downsampledImage(fileURL: URL, targetPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetPixelSize, 1)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private static func maximumFrameCount(
        for source: CGImageSource,
        budget: ZoomyAnimatedImageDecodeBudget
    ) -> Int {
        let pixelSize = pixelSize(for: source)
        let maxDimension = max(pixelSize.width, pixelSize.height, 1)
        let scale = min(1, Double(budget.maximumPixelSize) / maxDimension)
        let pixelsPerFrame = max(Int((pixelSize.width * scale * pixelSize.height * scale).rounded(.up)), 1)
        let pixelLimitedFrameCount = max(budget.maximumDecodedPixels / pixelsPerFrame, 1)
        return max(1, min(budget.maximumFrameCount, pixelLimitedFrameCount))
    }

    private static func effectiveThumbnailPixelSize(
        source: CGImageSource,
        budget: ZoomyAnimatedImageDecodeBudget
    ) -> Int {
        let pixelSize = pixelSize(for: source)
        return max(1, min(budget.maximumPixelSize, Int(max(pixelSize.width, pixelSize.height, 1))))
    }

    private static func pixelSize(for source: CGImageSource) -> (width: Double, height: Double) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (1, 1)
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 1
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 1
        return (max(width, 1), max(height, 1))
    }

    private static func persistTemporaryFile(
        at sourceURL: URL,
        originalURL: URL,
        fallbackExtension: String
    ) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        trimTemporaryFiles(in: directory)
        let destinationURL = directory.appending(
            path: "\(UUID().uuidString).\(preferredFileExtension(for: originalURL, fallback: fallbackExtension))"
        )
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private static func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: temporaryDirectoryName, directoryHint: .isDirectory)
    }

    private static func removeTemporaryFile(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func trimTemporaryFiles(in directory: URL) {
        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys)
        ) else { return }

        let expirationDate = Date().addingTimeInterval(-maximumTemporaryFileAge)
        var entries = fileURLs.compactMap { fileURL -> (url: URL, bytes: Int, date: Date)? in
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true
            else { return nil }
            return (fileURL, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }

        for entry in entries where entry.date < expirationDate {
            removeTemporaryFile(entry.url)
        }
        entries.removeAll { $0.date < expirationDate }
        entries.sort { $0.date > $1.date }

        var remainingCount = entries.count
        var remainingBytes = entries.reduce(0) { $0 + $1.bytes }
        let protectedNewestFileCount = min(2, entries.count)
        for entry in entries.reversed() {
            guard remainingCount > protectedNewestFileCount,
                  (remainingCount > maximumTemporaryFileCount || remainingBytes > maximumTemporaryFileBytes)
            else { break }
            removeTemporaryFile(entry.url)
            remainingCount -= 1
            remainingBytes -= entry.bytes
        }
    }

    private static func requestLivePhoto(
        imageFileURL: URL,
        videoFileURL: URL,
        placeholderImage: UIImage?
    ) async -> PHLivePhoto? {
        await withCheckedContinuation { continuation in
            var didResume = false
            PHLivePhoto.request(
                withResourceFileURLs: [imageFileURL, videoFileURL],
                placeholderImage: placeholderImage,
                targetSize: .zero,
                contentMode: .aspectFit
            ) { livePhoto, info in
                // Bilibili resources often are not Apple-authored Live Photos. The request
                // may only produce a degraded/nil callback; resume immediately so the
                // paired video fallback can be shown instead of leaving the viewer loading.
                _ = info[PHLivePhotoInfoIsDegradedKey]
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: livePhoto)
            }
        }
    }

    private static func preferredFileExtension(for url: URL?, fallback: String) -> String {
        guard let absoluteString = url?.absoluteString.lowercased() else { return fallback }
        for fileExtension in ["gif", "jpg", "jpeg", "png", "heic", "heif", "webp", "mov", "mp4"] {
            if absoluteString.contains(".\(fileExtension)") {
                return fileExtension
            }
        }
        return fallback
    }
}

private struct ZoomyViewerPageControl: UIViewRepresentable {
    let numberOfPages: Int
    let currentPage: Int

    private var indicatorColor: UIColor {
        .label
    }

    func makeUIView(context _: Context) -> UIPageControl {
        let control = UIPageControl()
        control.isUserInteractionEnabled = false
        control.allowsContinuousInteraction = false
        control.backgroundStyle = .minimal
        return control
    }

    func updateUIView(_ control: UIPageControl, context _: Context) {
        control.numberOfPages = numberOfPages
        control.currentPage = min(max(currentPage, 0), max(numberOfPages - 1, 0))
        control.isHidden = numberOfPages <= 1
        control.currentPageIndicatorTintColor = indicatorColor
        control.pageIndicatorTintColor = indicatorColor.withAlphaComponent(0.36)
    }
}

private final class ZoomyDismissPanGestureController: NSObject, UIGestureRecognizerDelegate {
    var canBegin: () -> Bool = { false }
    var onChanged: (CGFloat) -> Void = { _ in }
    var onEnded: (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }

    private lazy var recognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        return recognizer
    }()
    private var prioritizedRecognizers = Set<ObjectIdentifier>()

    func install(on view: UIView) {
        guard recognizer.view !== view else { return }
        recognizer.view?.removeGestureRecognizer(recognizer)
        view.addGestureRecognizer(recognizer)
        if let scrollView = view as? UIScrollView {
            prioritize(over: scrollView.panGestureRecognizer)
        }
    }

    func prioritizeAncestorPanGestures(from view: UIView) {
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                prioritize(over: scrollView.panGestureRecognizer)
            }
            ancestor = current.superview
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === recognizer, canBegin() else { return false }
        let velocity = recognizer.velocity(in: recognizer.view)
        return ZoomyViewerDismissGesturePolicy.isDownwardVerticalPull(
            CGSize(width: velocity.x, height: velocity.y)
        )
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === recognizer && otherGestureRecognizer is UIPanGestureRecognizer
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translationY = max(recognizer.translation(in: recognizer.view).y, 0)
        switch recognizer.state {
        case .began, .changed:
            onChanged(translationY)
        case .ended:
            let velocityY = recognizer.velocity(in: recognizer.view).y
            onEnded(translationY, velocityY, false)
        case .cancelled, .failed:
            onEnded(translationY, 0, true)
        case .possible:
            break
        @unknown default:
            onEnded(translationY, 0, true)
        }
    }

    private func prioritize(over otherGestureRecognizer: UIGestureRecognizer) {
        guard otherGestureRecognizer !== recognizer else { return }
        guard recognizer.state == .possible,
              otherGestureRecognizer.state == .possible
        else { return }
        let identifier = ObjectIdentifier(otherGestureRecognizer)
        guard prioritizedRecognizers.insert(identifier).inserted else { return }
        otherGestureRecognizer.require(toFail: recognizer)
    }
}

private struct ZoomyLiveVideoView: UIViewRepresentable {
    let videoURL: URL
    let placeholderImage: UIImage
    let isDismissGestureEnabled: Bool
    let onTapExit: () -> Void
    let onDismissDragChanged: (CGFloat) -> Void
    let onDismissDragEnded: (CGFloat, CGFloat, Bool) -> Void

    func makeUIView(context _: Context) -> ZoomyLiveVideoHostView {
        let view = ZoomyLiveVideoHostView()
        view.isDismissGestureEnabled = isDismissGestureEnabled
        view.onTapExit = onTapExit
        view.onDismissDragChanged = onDismissDragChanged
        view.onDismissDragEnded = onDismissDragEnded
        view.setVideo(url: videoURL, placeholderImage: placeholderImage)
        return view
    }

    func updateUIView(_ view: ZoomyLiveVideoHostView, context _: Context) {
        view.isDismissGestureEnabled = isDismissGestureEnabled
        view.onTapExit = onTapExit
        view.onDismissDragChanged = onDismissDragChanged
        view.onDismissDragEnded = onDismissDragEnded
        view.setVideo(url: videoURL, placeholderImage: placeholderImage)
    }
}

private final class ZoomyLiveVideoHostView: UIView, UIGestureRecognizerDelegate {
    var isDismissGestureEnabled = false
    var onTapExit: (() -> Void)?
    var onDismissDragChanged: ((CGFloat) -> Void)?
    var onDismissDragEnded: ((CGFloat, CGFloat, Bool) -> Void)?

    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var currentURL: URL?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    private lazy var dismissPanController: ZoomyDismissPanGestureController = {
        let controller = ZoomyDismissPanGestureController()
        controller.canBegin = { [weak self] in self?.isDismissGestureEnabled == true }
        controller.onChanged = { [weak self] translationY in
            self?.onDismissDragChanged?(translationY)
        }
        controller.onEnded = { [weak self] translationY, velocityY, cancelled in
            self?.onDismissDragEnded?(translationY, velocityY, cancelled)
        }
        return controller
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.clear.cgColor
        layer.addSublayer(playerLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        addGestureRecognizer(tap)
        dismissPanController.install(on: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        player?.pause()
    }

    func setVideo(url: URL, placeholderImage _: UIImage) {
        guard currentURL != url else {
            if player?.rate == 0 { player?.play() }
            return
        }
        currentURL = url
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        self.player = player
        playerLayer.player = player
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [player] _ in
            player.seek(to: .zero) { _ in player.play() }
        }
        player.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        dismissPanController.prioritizeAncestorPanGestures(from: self)
    }

    @objc private func handleTap() {
        onTapExit?()
    }
}

private struct ZoomyLivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let placeholderImage: UIImage
    let isDismissGestureEnabled: Bool
    let onTapExit: () -> Void
    let onDismissDragChanged: (CGFloat) -> Void
    let onDismissDragEnded: (CGFloat, CGFloat, Bool) -> Void

    func makeUIView(context _: Context) -> ZoomyLivePhotoHostView {
        let view = ZoomyLivePhotoHostView()
        view.isDismissGestureEnabled = isDismissGestureEnabled
        view.onTapExit = onTapExit
        view.onDismissDragChanged = onDismissDragChanged
        view.onDismissDragEnded = onDismissDragEnded
        return view
    }

    func updateUIView(_ view: ZoomyLivePhotoHostView, context _: Context) {
        view.isDismissGestureEnabled = isDismissGestureEnabled
        view.onTapExit = onTapExit
        view.onDismissDragChanged = onDismissDragChanged
        view.onDismissDragEnded = onDismissDragEnded
        view.setLivePhoto(livePhoto, placeholderImage: placeholderImage)
    }
}

private final class ZoomyLivePhotoHostView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var isDismissGestureEnabled = false
    var onTapExit: (() -> Void)?
    var onDismissDragChanged: ((CGFloat) -> Void)?
    var onDismissDragEnded: ((CGFloat, CGFloat, Bool) -> Void)?

    private let scrollView = UIScrollView()
    private let livePhotoView = PHLivePhotoView()
    private var currentLivePhotoIdentifier: ObjectIdentifier?
    private var placeholderImageSize: CGSize = .zero
    private var lastLayoutSize: CGSize = .zero
    private lazy var dismissPanController: ZoomyDismissPanGestureController = {
        let controller = ZoomyDismissPanGestureController()
        controller.canBegin = { [weak self] in
            guard let self else { return false }
            return self.isDismissGestureEnabled
                && self.scrollView.zoomScale <= self.scrollView.minimumZoomScale + 0.01
        }
        controller.onChanged = { [weak self] translationY in
            self?.onDismissDragChanged?(translationY)
        }
        controller.onEnded = { [weak self] translationY, velocityY, cancelled in
            self?.onDismissDragEnded?(translationY, velocityY, cancelled)
        }
        return controller
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        livePhotoView.backgroundColor = .clear
        livePhotoView.contentMode = .scaleAspectFit
        livePhotoView.isMuted = true
        scrollView.addSubview(livePhotoView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        tap.numberOfTapsRequired = 1
        tap.delegate = self

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        tap.require(toFail: doubleTap)

        scrollView.addGestureRecognizer(doubleTap)
        scrollView.addGestureRecognizer(tap)
        dismissPanController.install(on: scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLivePhoto(_ livePhoto: PHLivePhoto, placeholderImage: UIImage) {
        let identifier = ObjectIdentifier(livePhoto)
        guard currentLivePhotoIdentifier != identifier else { return }
        currentLivePhotoIdentifier = identifier
        placeholderImageSize = placeholderImage.size
        livePhotoView.livePhoto = livePhoto
        resetZoomLayout()
        livePhotoView.startPlayback(with: .full)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dismissPanController.prioritizeAncestorPanGestures(from: self)
        scrollView.frame = bounds
        guard bounds.size != lastLayoutSize else {
            centerContent()
            return
        }
        lastLayoutSize = bounds.size
        resetZoomLayout()
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        livePhotoView
    }

    func scrollViewDidZoom(_: UIScrollView) {
        centerContent()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer
    }

    @objc private func handleSingleTap() {
        onTapExit?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard livePhotoView.livePhoto != nil else { return }
        let targetScale: CGFloat
        if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 {
            targetScale = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale * 2.4, 2.4))
        } else {
            targetScale = scrollView.minimumZoomScale
        }

        if targetScale <= scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let location = recognizer.location(in: livePhotoView)
            scrollView.zoom(to: zoomRect(for: targetScale, centeredAt: location), animated: true)
        }
    }

    private func resetZoomLayout() {
        guard bounds.width > 1,
              bounds.height > 1,
              placeholderImageSize.width > 0,
              placeholderImageSize.height > 0
        else { return }

        scrollView.zoomScale = 1
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5

        let fittedSize = aspectFitSize(imageSize: placeholderImageSize, boundsSize: bounds.size)
        livePhotoView.frame = CGRect(origin: .zero, size: fittedSize)
        scrollView.contentSize = fittedSize
        centerContent()
    }

    private func centerContent() {
        let horizontalInset = max((bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let verticalInset = max((bounds.height - scrollView.contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func aspectFitSize(imageSize: CGSize, boundsSize: CGSize) -> CGSize {
        let scale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    private func zoomRect(for scale: CGFloat, centeredAt center: CGPoint) -> CGRect {
        let width = scrollView.bounds.width / scale
        let height = scrollView.bounds.height / scale
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

}

private struct ZoomyZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let isDismissGestureEnabled: Bool
    let onTapExit: () -> Void
    let onDismissDragChanged: (CGFloat) -> Void
    let onDismissDragEnded: (CGFloat, CGFloat, Bool) -> Void

    func makeUIView(context _: Context) -> ZoomyZoomableImageHostView {
        let view = ZoomyZoomableImageHostView()
        view.isDismissGestureEnabled = isDismissGestureEnabled
        view.onTapExit = onTapExit
        view.onDismissDragChanged = onDismissDragChanged
        view.onDismissDragEnded = onDismissDragEnded
        return view
    }

    func updateUIView(_ view: ZoomyZoomableImageHostView, context _: Context) {
        view.isDismissGestureEnabled = isDismissGestureEnabled
        view.onTapExit = onTapExit
        view.onDismissDragChanged = onDismissDragChanged
        view.onDismissDragEnded = onDismissDragEnded
        view.setImage(image)
    }
}

private final class ZoomyZoomableImageHostView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var isDismissGestureEnabled = false
    var onTapExit: (() -> Void)?
    var onDismissDragChanged: ((CGFloat) -> Void)?
    var onDismissDragEnded: ((CGFloat, CGFloat, Bool) -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var currentImageIdentifier: ObjectIdentifier?
    private var lastLayoutSize: CGSize = .zero
    private var usesLongImageScrolling = false
    private lazy var dismissPanController: ZoomyDismissPanGestureController = {
        let controller = ZoomyDismissPanGestureController()
        controller.canBegin = { [weak self] in
            guard let self else { return false }
            return self.isDismissGestureEnabled
                && !self.usesLongImageScrolling
                && self.scrollView.zoomScale <= self.scrollView.minimumZoomScale + 0.01
        }
        controller.onChanged = { [weak self] translationY in
            self?.onDismissDragChanged?(translationY)
        }
        controller.onEnded = { [weak self] translationY, velocityY, cancelled in
            self?.onDismissDragEnded?(translationY, velocityY, cancelled)
        }
        return controller
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isDirectionalLockEnabled = true
        addSubview(scrollView)

        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        scrollView.addSubview(imageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        tap.numberOfTapsRequired = 1
        tap.delegate = self

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        tap.require(toFail: doubleTap)

        scrollView.addGestureRecognizer(doubleTap)
        scrollView.addGestureRecognizer(tap)
        dismissPanController.install(on: scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        let identifier = ObjectIdentifier(image)
        guard currentImageIdentifier != identifier else { return }
        let previousImage = imageView.image
        let viewport = captureViewport()
        currentImageIdentifier = identifier
        imageView.image = image
        if image.images != nil {
            imageView.startAnimating()
        }
        resetZoomLayout()
        if let viewport,
           let previousImage,
           aspectRatiosAreCompatible(previousImage.size, image.size) {
            restoreViewport(viewport)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dismissPanController.prioritizeAncestorPanGestures(from: self)
        scrollView.frame = bounds
        guard bounds.size != lastLayoutSize else {
            centerImage()
            return
        }
        lastLayoutSize = bounds.size
        resetZoomLayout()
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_: UIScrollView) {
        centerImage()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer
    }

    @objc private func handleSingleTap() {
        onTapExit?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }
        let targetScale: CGFloat
        if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 {
            targetScale = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale * 2.4, 2.4))
        } else {
            targetScale = scrollView.minimumZoomScale
        }

        if targetScale <= scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let location = recognizer.location(in: imageView)
            scrollView.zoom(to: zoomRect(for: targetScale, centeredAt: location), animated: true)
        }
    }

    private func resetZoomLayout() {
        guard let image = imageView.image,
              bounds.width > 1,
              bounds.height > 1,
              image.size.width > 0,
              image.size.height > 0
        else { return }

        scrollView.zoomScale = 1
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5

        let layout = ZoomyViewerImageSizing.initialLayout(
            imageSize: image.size,
            boundsSize: bounds.size
        )
        usesLongImageScrolling = layout.usesLongImageScrolling
        scrollView.alwaysBounceVertical = usesLongImageScrolling
        imageView.frame = CGRect(origin: .zero, size: layout.contentSize)
        scrollView.contentSize = layout.contentSize
        centerImage()
        scrollView.setContentOffset(
            CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top),
            animated: false
        )
    }

    private func centerImage() {
        let horizontalInset = max((bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let verticalInset = max((bounds.height - scrollView.contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: usesLongImageScrolling ? 96 : verticalInset,
            right: horizontalInset
        )
    }

    private struct ViewportSnapshot {
        let zoomScale: CGFloat
        let normalizedCenter: CGPoint
    }

    private func captureViewport() -> ViewportSnapshot? {
        guard imageView.image != nil,
              imageView.bounds.width > 0,
              imageView.bounds.height > 0
        else { return nil }
        let center = imageView.convert(
            CGPoint(x: bounds.midX, y: bounds.midY),
            from: self
        )
        return ViewportSnapshot(
            zoomScale: scrollView.zoomScale,
            normalizedCenter: CGPoint(
                x: min(max(center.x / imageView.bounds.width, 0), 1),
                y: min(max(center.y / imageView.bounds.height, 0), 1)
            )
        )
    }

    private func restoreViewport(_ viewport: ViewportSnapshot) {
        let targetScale = min(
            max(viewport.zoomScale, scrollView.minimumZoomScale),
            scrollView.maximumZoomScale
        )
        scrollView.setZoomScale(targetScale, animated: false)
        layoutIfNeeded()

        let imagePoint = CGPoint(
            x: imageView.bounds.width * viewport.normalizedCenter.x,
            y: imageView.bounds.height * viewport.normalizedCenter.y
        )
        let scrollPoint = imageView.convert(imagePoint, to: scrollView)
        let proposedOffset = CGPoint(
            x: scrollPoint.x - scrollView.bounds.width * 0.5,
            y: scrollPoint.y - scrollView.bounds.height * 0.5
        )
        scrollView.setContentOffset(clampedContentOffset(proposedOffset), animated: false)
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let minimumX = -scrollView.contentInset.left
        let minimumY = -scrollView.contentInset.top
        let maximumX = max(
            minimumX,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right
        )
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        )
        return CGPoint(
            x: min(max(offset.x, minimumX), maximumX),
            y: min(max(offset.y, minimumY), maximumY)
        )
    }

    private func aspectRatiosAreCompatible(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else { return false }
        let lhsRatio = lhs.width / lhs.height
        let rhsRatio = rhs.width / rhs.height
        return abs(lhsRatio - rhsRatio) / max(lhsRatio, rhsRatio) < 0.04
    }

    private func zoomRect(for scale: CGFloat, centeredAt center: CGPoint) -> CGRect {
        let width = scrollView.bounds.width / scale
        let height = scrollView.bounds.height / scale
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }
}
