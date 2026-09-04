import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private struct FeedbackAttachment: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let contentType: UTType

    init(url: URL, contentType: UTType) {
        id = UUID()
        self.url = url
        self.contentType = contentType
    }

    var title: String {
        url.lastPathComponent
    }

    var icon: String {
        contentType.conforms(to: .movie) ? "video.fill" : "photo.fill"
    }
}

@MainActor
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var history = FeedbackHistoryStore.shared

    @State private var phoneModel = ""
    @State private var phoneSystem = ""
    @State private var problem = ""
    @State private var attachments: [FeedbackAttachment] = []
    @State private var showPhotoPicker = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !phoneModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phoneSystem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !problem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
    }

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(beansLocalized("问题反馈", "Feedback"))
                                .font(BeansFont.appFont(24, .bold))
                                .foregroundStyle(Color.beansLabel)
                            Text(beansLocalized("请填写设备信息和遇到的问题；图片与视频可选。", "Device details and an issue description are required. Images and videos are optional."))
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                        }

                        if !history.entries.isEmpty {
                            feedbackHistorySection
                        }

                        feedbackField(
                            title: beansLocalized("手机型号", "Phone model"),
                            prompt: beansLocalized("例如：iPhone 16 Pro", "For example: iPhone 16 Pro"),
                            text: $phoneModel
                        )
                        feedbackField(
                            title: beansLocalized("手机系统", "System version"),
                            prompt: beansLocalized("例如：iOS 26.0", "For example: iOS 26.0"),
                            text: $phoneSystem
                        )

                        VStack(alignment: .leading, spacing: 9) {
                            Text(beansLocalized("遇到的问题", "Issue"))
                                .font(BeansFont.appFont(13, .semibold))
                                .foregroundStyle(Color.beansLabel)
                            ZStack(alignment: .topLeading) {
                                if problem.isEmpty {
                                    Text(beansLocalized("请描述出现问题时的操作和现象", "Describe what you did and what happened"))
                                        .font(BeansFont.appFont(13))
                                        .foregroundStyle(Color.beansComment.opacity(0.72))
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 12)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $problem)
                                    .font(BeansFont.appFont(13))
                                    .foregroundStyle(Color.beansLabel)
                                    .frame(minHeight: 120)
                                    .padding(7)
                            }
                            .background {
                                BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(beansLocalized("附件", "Attachments"))
                                        .font(BeansFont.appFont(13, .semibold))
                                        .foregroundStyle(Color.beansLabel)
                                    Text(beansLocalized("可选：图片或视频", "Optional: images or videos"))
                                        .font(BeansFont.appFont(11))
                                        .foregroundStyle(Color.beansComment)
                                }
                                Spacer()
                                Button {
                                    showPhotoPicker = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.beansAmber)
                                        .frame(width: 32, height: 32)
                                        .background {
                                            BeansSurface(shape: Circle())
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(beansLocalized("添加附件", "Add attachment"))
                            }

                            if !attachments.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(attachments) { attachment in
                                        HStack(spacing: 10) {
                                            Image(systemName: attachment.icon)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(Color.beansAmber)
                                                .frame(width: 22)
                                            Text(attachment.title)
                                                .font(BeansFont.appFont(12))
                                                .foregroundStyle(Color.beansLabel)
                                                .lineLimit(1)
                                            Spacer()
                                            Button {
                                                removeAttachment(attachment)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(Color.beansComment.opacity(0.72))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(beansLocalized("移除附件", "Remove attachment"))
                                        }
                                        .padding(.vertical, 10)
                                        if attachment.id != attachments.last?.id {
                                            Divider().overlay(Color.beansComment.opacity(0.14))
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .background {
                                    BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }

                        Button {
                            submit()
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isSubmitting
                                     ? beansLocalized("正在提交", "Submitting")
                                     : beansLocalized("提交反馈", "Submit feedback"))
                            }
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(canSubmit ? Color.black : Color.beansComment.opacity(0.42), in: Capsule())
                        }
                        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
                        .disabled(!canSubmit)
                    }
                    .padding(20)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle(beansLocalized("反馈", "Feedback"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(beansLocalized("完成", "Done")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            FeedbackPhotoPicker { results in
                Task { @MainActor in
                    await importPhotoResults(results)
                }
            }
        }
        .alert(beansLocalized("提交失败", "Submission failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(beansLocalized("知道了", "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func feedbackField(title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BeansFont.appFont(13, .semibold))
                .foregroundStyle(Color.beansLabel)
            TextField(prompt, text: text)
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansLabel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background {
                    BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
        }
    }

    private var feedbackHistorySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(beansLocalized("反馈记录", "Feedback history"))
                .font(BeansFont.appFont(13, .semibold))
                .foregroundStyle(Color.beansLabel)
            VStack(spacing: 0) {
                ForEach(history.entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(entry.submittedAt, style: .date)
                            Spacer()
                            Text(entry.attachmentCount == 0
                                 ? beansLocalized("无附件", "No attachments")
                                 : beansLocalized("附件 \(entry.attachmentCount)", "\(entry.attachmentCount) attachments"))
                        }
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                        Text(entry.problem)
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansLabel)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 10)
                    if entry.id != history.entries.last?.id {
                        Divider().overlay(Color.beansComment.opacity(0.14))
                    }
                }
            }
            .padding(.horizontal, 12)
            .background {
                BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func addAttachment(_ sourceURL: URL) {
        let shouldStop = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStop {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let contentType = UTType(filenameExtension: sourceURL.pathExtension) ?? .data
        guard contentType.conforms(to: .image) || contentType.conforms(to: .movie) else {
            errorMessage = beansLocalized("只能添加图片或视频附件。", "Only image and video attachments are supported.")
            return
        }
        guard let copyURL = FeedbackAttachmentStore.copyToTemporaryDirectory(sourceURL) else {
            errorMessage = beansLocalized("附件读取失败，请重新选择。", "The attachment could not be read. Please choose it again.")
            return
        }
        attachments.append(FeedbackAttachment(url: copyURL, contentType: contentType))
    }

    private func importPhotoResults(_ results: [PHPickerResult]) async {
        for result in results {
            let provider = result.itemProvider
            let contentType = provider.registeredTypeIdentifiers
                .compactMap { UTType($0) }
                .first(where: {
                $0.conforms(to: UTType.image) || $0.conforms(to: UTType.movie)
                }) ?? .data
            guard contentType.conforms(to: UTType.image) || contentType.conforms(to: UTType.movie) else {
                errorMessage = beansLocalized("只能添加图片或视频附件。", "Only image and video attachments are supported.")
                continue
            }

            guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: contentType) == true
            }), let data = try? await loadPhotoData(from: provider, typeIdentifier: typeIdentifier) else {
                errorMessage = beansLocalized("附件读取失败，请重新选择。", "The attachment could not be read. Please choose it again.")
                continue
            }

            let fileExtension = contentType.preferredFilenameExtension
                ?? (contentType.conforms(to: UTType.movie) ? "mov" : "jpg")
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("BeansFeedbackUploads", isDirectory: true)
            let destination = directory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: destination, options: Data.WritingOptions.atomic)
                attachments.append(FeedbackAttachment(url: destination, contentType: contentType))
            } catch {
                errorMessage = beansLocalized("附件保存失败，请重新选择。", "The attachment could not be saved. Please choose it again.")
            }
        }
    }

    private func loadPhotoData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    private func removeAttachment(_ attachment: FeedbackAttachment) {
        try? FileManager.default.removeItem(at: attachment.url)
        attachments.removeAll { $0.id == attachment.id }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        let currentAttachments = attachments.map(\.url)
        Task {
            do {
                let result = try await DeviceReporter.shared.submitFeedback(
                    phoneModel: phoneModel,
                    phoneSystem: phoneSystem,
                    problem: problem,
                    attachmentURLs: currentAttachments
                )
                await MainActor.run {
                    isSubmitting = false
                    if result.downloadUnlocked {
                        UserDefaults.standard.set(true, forKey: BeansBackendSettings.downloadUnlockKey)
                    }
                    history.record(
                        feedbackID: result.feedbackID,
                        submittedAt: result.submittedAt,
                        problem: problem,
                        attachmentCount: currentAttachments.count
                    )
                    currentAttachments.forEach { try? FileManager.default.removeItem(at: $0) }
                    ToastCenter.shared.show(
                        result.downloadUnlocked
                            ? beansLocalized("反馈已提交，下载功能已解锁", "Feedback submitted. Downloads unlocked.")
                            : beansLocalized("反馈已提交", "Feedback submitted.")
                    )
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct FeedbackPhotoPicker: UIViewControllerRepresentable {
    let onPick: ([PHPickerResult]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 4
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([PHPickerResult]) -> Void

        init(onPick: @escaping ([PHPickerResult]) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPick(results)
            picker.dismiss(animated: true)
        }
    }
}

private enum FeedbackAttachmentStore {
    static func copyToTemporaryDirectory(_ sourceURL: URL) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeansFeedbackUploads", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(sourceURL.pathExtension)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
