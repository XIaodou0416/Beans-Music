import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CustomSongCoverCrop: Codable, Equatable {
    var zoom: CGFloat = 1
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    static let `default` = CustomSongCoverCrop()
}

struct CustomSongCoverSelection {
    let sourceURL: URL
    let crop: CustomSongCoverCrop
}

enum CustomCoverMediaKind: Equatable {
    case image
    case gif
    case video
}

enum CustomCoverMedia {
    static func kind(for url: URL) -> CustomCoverMediaKind {
        if url.pathExtension.lowercased() == "gif" {
            return .gif
        }
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) {
            return .video
        }
        return .image
    }

    static func usesAnimatedRenderer(for url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        switch kind(for: url) {
        case .gif, .video: return true
        case .image: return false
        }
    }

    static func previewImage(at url: URL) -> UIImage? {
        switch kind(for: url) {
        case .image, .gif:
            return UIImage(contentsOfFile: url.path)
        case .video:
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            return try? UIImage(cgImage: generator.copyCGImage(at: .zero, actualTime: nil))
        }
    }

    static func animatedGIF(at url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(contentsOfFile: url.path) }

        let frameLimit = min(count, 120)
        var images: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<frameLimit {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            images.append(UIImage(cgImage: cgImage))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                ?? 0.08
            duration += max(delay, 0.04)
        }
        guard !images.isEmpty else { return nil }
        return UIImage.animatedImage(with: images, duration: max(duration, 0.08 * Double(images.count)))
    }
}

@MainActor
final class CustomSongCoverStore: ObservableObject {
    static let shared = CustomSongCoverStore()

    @Published private(set) var revision = 0

    private struct Entry: Codable, Equatable {
        let filename: String
        let crop: CustomSongCoverCrop
    }

    private let legacyDefaultsKey = "beans.player.customSongCovers.v1"
    private let defaultsKey = "beans.player.customSongCovers.v2"
    private let directory: URL
    private var entries: [String: Entry]

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansCustomSongCovers", isDirectory: true)
        entries = Self.loadEntries(defaultsKey: defaultsKey, legacyDefaultsKey: legacyDefaultsKey)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pruneMissingFiles()
    }

    func url(for song: Song?) -> URL? {
        guard let song, let entry = entries[song.identityKey] else { return nil }
        let url = directory.appendingPathComponent(entry.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func crop(for url: URL?) -> CustomSongCoverCrop {
        guard let url else { return .default }
        return entries.values.first(where: { $0.filename == url.lastPathComponent })?.crop ?? .default
    }

    func isStoredCover(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        return entries.values.contains { $0.filename == url.lastPathComponent }
    }

    func hasCover(for song: Song?) -> Bool {
        url(for: song) != nil
    }

    func saveCover(from sourceURL: URL, crop: CustomSongCoverCrop = .default, for song: Song) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let sourceData = try Data(contentsOf: sourceURL)
        guard !sourceData.isEmpty else { throw CustomSongCoverError.invalidMedia }

        let mediaKind = CustomCoverMedia.kind(for: sourceURL)
        let filename: String
        let dataToWrite: Data
        switch mediaKind {
        case .image:
            guard let jpeg = preparedJPEG(from: sourceData) else {
                throw CustomSongCoverError.invalidMedia
            }
            filename = UUID().uuidString.lowercased() + ".jpg"
            dataToWrite = jpeg
        case .gif, .video:
            guard sourceData.count <= 50 * 1024 * 1024 else {
                throw CustomSongCoverError.fileTooLarge
            }
            let ext = sourceURL.pathExtension.isEmpty
                ? (mediaKind == .gif ? "gif" : "mp4")
                : sourceURL.pathExtension.lowercased()
            filename = UUID().uuidString.lowercased() + "." + ext
            dataToWrite = sourceData
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(filename)
        try dataToWrite.write(to: destination, options: .atomic)

        if let previous = entries.updateValue(Entry(filename: filename, crop: crop), forKey: song.identityKey), previous.filename != filename {
            let previousURL = directory.appendingPathComponent(previous.filename)
            try? FileManager.default.removeItem(at: previousURL)
            BeansImageFileCache.remove(previousURL.path)
        }
        persist()
        BeansImageFileCache.remove(destination.path)
        revision &+= 1
    }

    func removeCover(for song: Song?) {
        guard let song, let entry = entries.removeValue(forKey: song.identityKey) else { return }
        let url = directory.appendingPathComponent(entry.filename)
        try? FileManager.default.removeItem(at: url)
        BeansImageFileCache.remove(url.path)
        persist()
        revision &+= 1
    }

    private static func loadEntries(defaultsKey: String, legacyDefaultsKey: String) -> [String: Entry] {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            return decoded
        }
        let legacy = UserDefaults.standard.dictionary(forKey: legacyDefaultsKey) as? [String: String] ?? [:]
        return legacy.mapValues { Entry(filename: $0, crop: .default) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func pruneMissingFiles() {
        let retained = entries.filter { _, entry in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.filename).path)
        }
        guard retained != entries else { return }
        entries = retained
        persist()
    }

    private func preparedJPEG(from data: Data) -> Data? {
        guard let source = UIImage(data: data) else { return nil }
        let longestSide = max(source.size.width, source.size.height)
        let targetSize: CGSize
        if longestSide > 1600 {
            let scale = 1600 / longestSide
            targetSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        } else {
            targetSize = source.size
        }
        let image: UIImage
        if targetSize != source.size {
            image = UIGraphicsImageRenderer(size: targetSize).image { _ in
                source.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        } else {
            image = source
        }
        return image.jpegData(compressionQuality: 0.84)
    }
}

enum CustomSongCoverError: LocalizedError {
    case invalidMedia
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidMedia: return "请选择有效的图片、GIF 或视频"
        case .fileTooLarge: return "视频或 GIF 不能超过 50 MB"
        }
    }
}

struct CustomSongCoverPicker: View {
    let onPick: (CustomSongCoverSelection) -> Void
    let onCancel: () -> Void

    @State private var sourceURL: URL?

    var body: some View {
        Group {
            if let sourceURL {
                CustomSongCoverCropEditor(
                    sourceURL: sourceURL,
                    onSave: { crop in onPick(CustomSongCoverSelection(sourceURL: sourceURL, crop: crop)) },
                    onCancel: cancel
                )
            } else {
                CustomSongCoverPhotoPicker(
                    onPick: { sourceURL = $0 },
                    onCancel: onCancel
                )
            }
        }
    }

    private func cancel() {
        if let sourceURL { try? FileManager.default.removeItem(at: sourceURL) }
        onCancel()
    }
}

private struct CustomSongCoverPhotoPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  let identifier = preferredTypeIdentifier(for: provider) else {
                onCancel()
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] sourceURL, _ in
                guard let self, let sourceURL,
                      let copiedURL = self.copyToTemporaryDirectory(sourceURL, typeIdentifier: identifier) else {
                    DispatchQueue.main.async { self?.onCancel() }
                    return
                }
                DispatchQueue.main.async { self.onPick(copiedURL) }
            }
        }

        private func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
            provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .movie) == true
            } ?? provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .image) == true
            }
        }

        private func copyToTemporaryDirectory(_ sourceURL: URL, typeIdentifier: String) -> URL? {
            let type = UTType(typeIdentifier)
            let ext = sourceURL.pathExtension.isEmpty
                ? (type?.preferredFilenameExtension ?? "dat")
                : sourceURL.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("beans-cover-" + UUID().uuidString.lowercased())
                .appendingPathExtension(ext)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                return destination
            } catch {
                return nil
            }
        }
    }
}

private struct CustomSongCoverCropEditor: View {
    let sourceURL: URL
    let onSave: (CustomSongCoverCrop) -> Void
    let onCancel: () -> Void

    @State private var previewImage: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var committedOffset = CGSize.zero
    @State private var cropReferenceSize: CGFloat = 300

    var body: some View {
        BeansNavigationStack {
            VStack(spacing: 20) {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        Color.black.opacity(0.9)
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: side, height: side)
                                .scaleEffect(zoom)
                                .offset(offset)
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                        Rectangle()
                            .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { cropReferenceSize = max(side, 1) }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoom = min(max(committedZoom * value, 1), 4)
                            }
                            .onEnded { _ in committedZoom = zoom }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                let limit = side * max(zoom - 1, 0) * 0.5
                                offset = CGSize(
                                    width: min(max(committedOffset.width + value.translation.width, -limit), limit),
                                    height: min(max(committedOffset.height + value.translation.height, -limit), limit)
                                )
                            }
                            .onEnded { _ in committedOffset = offset }
                    )
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 24)

                VStack(spacing: 8) {
                    Slider(value: $zoom, in: 1...4, step: 0.01)
                        .tint(Color.beansAmber)
                        .onChange(of: zoom) { _ in committedZoom = zoom }
                    Text("拖动调整位置，双指缩放裁剪区域")
                        .font(BeansFont.appFont(13, .medium))
                        .foregroundStyle(Color.beansComment)
                }
                .padding(.horizontal, 28)

                Button("重置裁剪") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        zoom = 1
                        committedZoom = 1
                        offset = .zero
                        committedOffset = .zero
                    }
                }
                .font(BeansFont.appFont(14, .semibold))
                .foregroundStyle(Color.beansAmber)
                Spacer(minLength: 4)
            }
            .padding(.top, 18)
            .navigationTitle("裁剪封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用") {
                        let crop = CustomSongCoverCrop(
                            zoom: zoom,
                            offsetX: offset.width / cropReferenceSize,
                            offsetY: offset.height / cropReferenceSize
                        )
                        onSave(crop)
                    }
                    .disabled(previewImage == nil)
                }
            }
        }
        .task {
            previewImage = await Task.detached(priority: .userInitiated) {
                CustomCoverMedia.previewImage(at: sourceURL)
            }.value
        }
    }
}

struct CustomCoverMediaView: UIViewRepresentable {
    let url: URL
    let crop: CustomSongCoverCrop

    func makeUIView(context: Context) -> CustomCoverMediaUIView {
        let view = CustomCoverMediaUIView()
        view.configure(url: url, crop: crop)
        return view
    }

    func updateUIView(_ uiView: CustomCoverMediaUIView, context: Context) {
        uiView.configure(url: url, crop: crop)
    }
}

final class CustomCoverMediaUIView: UIView {
    private let imageView = UIImageView()
    private let videoHost = UIView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?
    private var currentKind: CustomCoverMediaKind?
    private var crop = CustomSongCoverCrop.default

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        videoHost.clipsToBounds = true
        addSubview(imageView)
        addSubview(videoHost)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.transform = .identity
        videoHost.transform = .identity
        imageView.frame = bounds
        videoHost.frame = bounds
        videoHost.layer.sublayers?.forEach { $0.frame = videoHost.bounds }
        applyCrop()
    }

    func configure(url: URL, crop: CustomSongCoverCrop) {
        let kind = CustomCoverMedia.kind(for: url)
        self.crop = crop
        guard currentURL != url || currentKind != kind else {
            applyCrop()
            return
        }
        currentURL = url
        currentKind = kind
        imageView.stopAnimating()
        imageView.image = nil
        player?.pause()
        player = nil
        looper = nil
        videoHost.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        switch kind {
        case .image:
            imageView.isHidden = false
            videoHost.isHidden = true
            imageView.image = UIImage(contentsOfFile: url.path)
        case .gif:
            imageView.isHidden = false
            videoHost.isHidden = true
            imageView.image = CustomCoverMedia.animatedGIF(at: url)
            imageView.startAnimating()
        case .video:
            imageView.isHidden = true
            videoHost.isHidden = false
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            self.player = player
            looper = AVPlayerLooper(player: player, templateItem: item)
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            videoHost.layer.addSublayer(layer)
            player.play()
        }
        setNeedsLayout()
    }

    private func applyCrop() {
        let scale = max(crop.zoom, 1)
        let offset = CGPoint(x: crop.offsetX * bounds.width, y: crop.offsetY * bounds.height)
        imageView.transform = CGAffineTransform(scaleX: scale, y: scale)
        imageView.center = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
        videoHost.transform = CGAffineTransform(scaleX: scale, y: scale)
        videoHost.center = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
    }
}
