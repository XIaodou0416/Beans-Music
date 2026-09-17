import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class CustomSongCoverStore: ObservableObject {
    static let shared = CustomSongCoverStore()

    @Published private(set) var revision = 0

    private let defaultsKey = "beans.player.customSongCovers.v1"
    private let directory: URL
    private var filenames: [String: String]

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansCustomSongCovers", isDirectory: true)
        filenames = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pruneMissingFiles()
    }

    func url(for song: Song?) -> URL? {
        guard let song, let filename = filenames[song.identityKey] else { return nil }
        let url = directory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func hasCover(for song: Song?) -> Bool {
        url(for: song) != nil
    }

    func saveCover(from sourceURL: URL, for song: Song) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let sourceData = try Data(contentsOf: sourceURL)
        guard let jpeg = preparedJPEG(from: sourceData) else {
            throw CustomSongCoverError.invalidImage
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = UUID().uuidString.lowercased() + ".jpg"
        let destination = directory.appendingPathComponent(filename)
        try jpeg.write(to: destination, options: .atomic)

        if let previous = filenames.updateValue(filename, forKey: song.identityKey), previous != filename {
            let previousURL = directory.appendingPathComponent(previous)
            try? FileManager.default.removeItem(at: previousURL)
            BeansImageFileCache.remove(previousURL.path)
        }
        persist()
        BeansImageFileCache.remove(destination.path)
        revision &+= 1
    }

    func removeCover(for song: Song?) {
        guard let song, let filename = filenames.removeValue(forKey: song.identityKey) else { return }
        let url = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        BeansImageFileCache.remove(url.path)
        persist()
        revision &+= 1
    }

    private func persist() {
        UserDefaults.standard.set(filenames, forKey: defaultsKey)
    }

    private func pruneMissingFiles() {
        let retained = filenames.filter { _, filename in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path)
        }
        guard retained != filenames else { return }
        filenames = retained
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
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "请选择有效的图片文件"
        }
    }
}

struct CustomSongCoverPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }
    }
}
