import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    /// System media surfaces expect square artwork. Normalize video frames before handing them
    /// to Now Playing so portrait source dimensions do not leak into the compact artwork layout.
    static func systemArtworkImage(at url: URL) -> UIImage? {
        guard let source = previewImage(at: url) else { return nil }
        let normalized = normalizedImage(source)
        let sourceSize = normalized.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return normalized }

        let side = min(max(sourceSize.width, sourceSize.height), 1600)
        let targetSize = CGSize(width: side, height: side)
        let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            normalized.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
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

final class CustomSongCoverStore: ObservableObject {
    static let shared = CustomSongCoverStore()

    @Published private(set) var revision = 0

    private struct Entry: Codable, Equatable {
        let filename: String
        let sourceCoverURL: String?
        let videoAudioEnabled: Bool?
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
        guard let song, var entry = entries[song.identityKey] else { return nil }
        let url = directory.appendingPathComponent(entry.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if entry.sourceCoverURL == nil, let sourceCoverURL = song.coverURL?.absoluteString {
            entry = Entry(
                filename: entry.filename,
                sourceCoverURL: sourceCoverURL,
                videoAudioEnabled: entry.videoAudioEnabled
            )
            entries[song.identityKey] = entry
            persist()
        }
        return url
    }

    func resolvedURL(for sourceURL: URL?) -> URL? {
        guard let sourceURL else { return nil }
        guard let entry = entries.values.first(where: { $0.sourceCoverURL == sourceURL.absoluteString }) else {
            return sourceURL
        }
        let customURL = directory.appendingPathComponent(entry.filename)
        return FileManager.default.fileExists(atPath: customURL.path) ? customURL : sourceURL
    }

    func isStoredCover(_ url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        return entries.values.contains { $0.filename == url.lastPathComponent }
    }

    func hasCover(for song: Song?) -> Bool {
        url(for: song) != nil
    }

    func isVideoCover(for song: Song?) -> Bool {
        guard let url = url(for: song) else { return false }
        return CustomCoverMedia.kind(for: url) == .video
    }

    func videoAudioEnabled(for url: URL?) -> Bool {
        guard let url else { return false }
        return entries.values.first(where: { $0.filename == url.lastPathComponent })?.videoAudioEnabled ?? false
    }

    func setVideoAudioEnabled(_ enabled: Bool, for song: Song?) {
        guard let song, let entry = entries[song.identityKey] else { return }
        entries[song.identityKey] = Entry(
            filename: entry.filename,
            sourceCoverURL: entry.sourceCoverURL,
            videoAudioEnabled: enabled
        )
        persist()
        revision &+= 1
        NotificationCenter.default.post(name: .beansCustomSongCoverDidChange, object: song.identityKey)
    }

    func saveCover(from sourceURL: URL, for song: Song) throws {
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
            let ext = sourceURL.pathExtension.isEmpty
                ? (mediaKind == .gif ? "gif" : "mp4")
                : sourceURL.pathExtension.lowercased()
            filename = UUID().uuidString.lowercased() + "." + ext
            dataToWrite = sourceData
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(filename)
        try dataToWrite.write(to: destination, options: .atomic)

        let entry = Entry(
            filename: filename,
            sourceCoverURL: song.coverURL?.absoluteString,
            videoAudioEnabled: false
        )
        if let previous = entries.updateValue(entry, forKey: song.identityKey), previous.filename != filename {
            let previousURL = directory.appendingPathComponent(previous.filename)
            try? FileManager.default.removeItem(at: previousURL)
            BeansImageFileCache.remove(previousURL.path)
        }
        persist()
        BeansImageFileCache.remove(destination.path)
        revision &+= 1
        NotificationCenter.default.post(name: .beansCustomSongCoverDidChange, object: song.identityKey)
    }

    func removeCover(for song: Song?) {
        guard let song, let entry = entries.removeValue(forKey: song.identityKey) else { return }
        let url = directory.appendingPathComponent(entry.filename)
        try? FileManager.default.removeItem(at: url)
        BeansImageFileCache.remove(url.path)
        persist()
        revision &+= 1
        NotificationCenter.default.post(name: .beansCustomSongCoverDidChange, object: song.identityKey)
    }

    private static func loadEntries(defaultsKey: String, legacyDefaultsKey: String) -> [String: Entry] {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            return decoded
        }
        let legacy = UserDefaults.standard.dictionary(forKey: legacyDefaultsKey) as? [String: String] ?? [:]
        return legacy.mapValues { Entry(filename: $0, sourceCoverURL: nil, videoAudioEnabled: false) }
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

    var errorDescription: String? {
        switch self {
        case .invalidMedia: return "请选择有效的图片、GIF 或视频"
        }
    }
}

extension Notification.Name {
    static let beansCustomSongCoverDidChange = Notification.Name("beans.customSongCoverDidChange")
}

struct CustomSongCoverPicker: View {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    var body: some View {
        CustomSongCoverPhotoPicker(onPick: onPick, onCancel: onCancel)
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

struct CustomCoverMediaView: UIViewRepresentable {
    let url: URL
    let isMuted: Bool

    func makeUIView(context: Context) -> CustomCoverMediaUIView {
        let view = CustomCoverMediaUIView()
        view.configure(url: url, isMuted: isMuted)
        return view
    }

    func updateUIView(_ uiView: CustomCoverMediaUIView, context: Context) {
        uiView.configure(url: url, isMuted: isMuted)
    }
}

final class CustomCoverMediaUIView: UIView {
    private let imageView = UIImageView()
    private let videoHost = UIView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoLayer: AVPlayerLayer?
    private var currentURL: URL?
    private var currentKind: CustomCoverMediaKind?

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
        videoLayer?.frame = videoHost.bounds
    }

    func configure(url: URL, isMuted: Bool) {
        let kind = CustomCoverMedia.kind(for: url)
        guard currentURL != url || currentKind != kind else {
            player?.isMuted = isMuted
            return
        }
        currentURL = url
        currentKind = kind
        imageView.stopAnimating()
        imageView.image = nil
        player?.pause()
        player = nil
        looper = nil
        videoLayer = nil
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
            player.isMuted = isMuted
            self.player = player
            looper = AVPlayerLooper(player: player, templateItem: item)
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            videoHost.layer.addSublayer(layer)
            videoLayer = layer
            player.play()
        }
        setNeedsLayout()
    }
}
