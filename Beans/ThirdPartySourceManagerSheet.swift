import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ThirdPartySourceManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UnblockSourceStore.shared

    @State private var importMode: ThirdPartySourceImportMode = .paste
    @State private var importText = ""
    @State private var importURL = ""
    @State private var importStatus: String?
    @State private var showImportErrorAlert = false
    @State private var importErrorMessage = ""
    @State private var showFilePicker = false
    @State private var editingDraft: ThirdPartySourceDraft?

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 14) {
                    headerCard
                    importCard
                    sourceListCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .background(GlassBackdrop())
            .navigationTitle(beansLocalized("自定义音源", "Custom Sources"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(beansLocalized("完成", "Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        editingDraft = ThirdPartySourceDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $editingDraft) { draft in
            SourceEditorSheet(draft: draft) { updated in
                store.upsert(updated.toSource())
            }
        }
        .fullScreenCover(isPresented: $showFilePicker) {
            SourceDocumentPicker(
                onPick: { url in
                    showFilePicker = false
                    Task { await importFile(url) }
                },
                onCancel: {
                    showFilePicker = false
                }
            )
            .ignoresSafeArea()
        }
        .alert(beansLocalized("导入失败", "Import Failed"), isPresented: $showImportErrorAlert) {
            Button(beansLocalized("知道了", "OK"), role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(beansLocalized("导入与管理", "Import & Manage"))
                        .font(BeansFont.appFont(18, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Text(beansLocalized("支持本地文件、远程 URL 和粘贴文本。", "Supports local files, remote URLs, and pasted text."))
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                }
                Spacer()
                Button {
                    editingDraft = ThirdPartySourceDraft()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black, in: Circle())
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.95))
            }

            if let importStatus {
                Text(importStatus)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansAmber)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 8, y: 3)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(beansLocalized("导入音源", "Import Sources"))
                    .font(BeansFont.appFont(15, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Picker("", selection: $importMode) {
                    ForEach(ThirdPartySourceImportMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Group {
                switch importMode {
                case .paste:
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $importText)
                            .frame(minHeight: 150)
                            .padding(8)
                            .background(Color.clear)
                            .modifier(ScrollContentBackgroundHidden())
                        if importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(beansLocalized("粘贴 JSON / 配置 / 脚本内容", "Paste JSON / config / script text"))
                                .font(BeansFont.appFont(13))
                                .foregroundStyle(Color.beansComment.opacity(0.8))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                        }
                    }
                case .url:
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(beansLocalized("输入远程音源地址", "Enter remote source URL"), text: $importURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(BeansFont.appFont(14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
                        Button {
                            Task { await importRemoteURL() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text(beansLocalized("识别并导入", "Recognize & Import"))
                            }
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.black, in: Capsule())
                        }
                        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
                    }
                case .file:
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            showFilePicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.badge.plus")
                                Text(beansLocalized("选择本地文件", "Choose Local File"))
                            }
                            .font(BeansFont.appFont(13, .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.black, in: Capsule())
                        }
                        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
                        Text(beansLocalized("支持 JSON、JS、TXT 等文本文件。", "Supports JSON, JS, TXT and other text files."))
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                    }
                }
            }

            if importMode != .url {
                Button {
                    Task { await importCurrentInput() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text(beansLocalized("识别并导入", "Recognize & Import"))
                    }
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.97))
            }

            Text(beansLocalized("支持 JSON 数组、单个配置、`SERVER_SCRIPT_CONFIG` 片段，以及 `@name` / `@template` 头部格式。", "Supports JSON arrays, single configs, `SERVER_SCRIPT_CONFIG` fragments, and `@name` / `@template` header-style blocks."))
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 8, y: 3)
    }

    private var sourceListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(beansLocalized("音源列表", "Source List"))
                    .font(BeansFont.appFont(15, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                Text("\(store.sources.count)")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }

            if store.sources.isEmpty {
                EmptyStateView(icon: "shippingbox.fill", text: beansLocalized("还没有音源，先导入一个吧。", "No sources yet. Import one first."))
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(store.sources.enumerated()), id: \.element.id) { index, source in
                        SourceRow(
                            source: source,
                            canMoveUp: index > 0,
                            canMoveDown: index < store.sources.count - 1,
                            onEdit: {
                                editingDraft = ThirdPartySourceDraft(source: source)
                            },
                            onRemove: {
                                if store.removeSource(id: source.id) {
                                    importStatus = beansLocalized("已删除音源：\(source.name)", "Deleted source: \(source.name)")
                                }
                            },
                            onMoveUp: {
                                store.moveSource(id: source.id, by: -1)
                            },
                            onMoveDown: {
                                store.moveSource(id: source.id, by: 1)
                            },
                            onToggle: { enabled in
                                store.updateEnabled(id: source.id, enabled: enabled)
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 8, y: 3)
    }

    private func importCurrentInput() async {
        do {
            let sources = try ThirdPartySourceImportParser.parse(
                text: importText,
                fallbackName: beansLocalized("粘贴导入", "Pasted Import")
            )
            try await finishImport(sources)
        } catch {
            await showImportError(message: error.localizedDescription)
        }
    }

    private func importRemoteURL() async {
        let trimmed = importURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            await showImportError(message: ThirdPartySourceImportError.invalidURL.localizedDescription)
            return
        }
        do {
            let sources = try await ThirdPartySourceImportParser.fetch(url: url)
            try await finishImport(sources)
        } catch {
            await showImportError(message: error.localizedDescription)
        }
    }

    private func importFile(_ url: URL) async {
        do {
            let sources = try ThirdPartySourceImportParser.parse(fileURL: url)
            try await finishImport(sources)
        } catch {
            await showImportError(message: error.localizedDescription)
        }
    }

    private func finishImport(_ sources: [ThirdPartySource]) async throws {
        let normalized = sources.map { source in
            var updated = source
            updated.id = UUID().uuidString
            updated.isPreset = false
            return updated
        }
        guard !normalized.isEmpty else {
            throw ThirdPartySourceImportError.noValidSource
        }
        await MainActor.run {
            store.addSources(normalized)
            importStatus = beansLocalized("已导入 \(normalized.count) 个音源", "Imported \(normalized.count) sources")
            importText = ""
            if importMode == .url { importURL = "" }
            BeansHaptics.success()
        }
    }

    @MainActor
    private func showImportError(message: String) {
        importErrorMessage = message
        showImportErrorAlert = true
    }
}

private enum ThirdPartySourceImportMode: String, CaseIterable, Identifiable {
    case paste
    case url
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: return beansLocalized("文本", "Text")
        case .url: return beansLocalized("链接", "URL")
        case .file: return beansLocalized("文件", "File")
        }
    }
}

private struct SourceRow: View {
    let source: ThirdPartySource
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onToggle: (Bool) -> Void

    private var subtitle: String {
        let platform = source.headers["source"].map { ThirdPartySourcePlatform(code: $0).title } ?? ""
        let parts = [
            source.kind.uppercased(),
            platform,
            source.urlPath
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(source.name)
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                            .lineLimit(1)
                        if source.isPreset {
                            Text(beansLocalized("预设", "Preset"))
                                .font(BeansFont.appFont(10, .medium))
                                .foregroundStyle(Color.beansAmber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.beansAmber.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { source.enabled }, set: onToggle))
                    .labelsHidden()
                    .tint(Color.beansAmber)
            }

            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Label(beansLocalized("编辑", "Edit"), systemImage: "slider.horizontal.3")
                        .foregroundStyle(Color.beansAmber)
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.96))

                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(!canMoveUp)
                .foregroundStyle(canMoveUp ? Color.beansAmber : Color.beansComment.opacity(0.35))

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDown)
                .foregroundStyle(canMoveDown ? Color.beansAmber : Color.beansComment.opacity(0.35))

                Spacer()

                if source.isPreset {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.beansComment)
                } else {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background {
            BeansSurface(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct ThirdPartySourceDraft: Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var kind: String = "keyword"
    var template: String = ""
    var urlPath: String = "url"
    var headersText: String = ""
    var enabled: Bool = true
    var isPreset: Bool = false
    var platform: ThirdPartySourcePlatform = .all

    init() {}

    init(source: ThirdPartySource) {
        id = source.id
        name = source.name
        kind = source.kind
        template = source.template
        urlPath = source.urlPath
        enabled = source.enabled
        isPreset = source.isPreset
        if let code = source.headers["source"] {
            platform = ThirdPartySourcePlatform(code: code)
        }
        headersText = source.headers
            .filter { $0.key != "source" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    func toSource() -> ThirdPartySource {
        var headers = Self.parseHeaders(headersText)
        if let code = platform.code {
            headers["source"] = code
        }
        return ThirdPartySource(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? beansLocalized("未命名音源", "Untitled source") : name,
            kind: kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "keyword" : kind,
            template: template.trimmingCharacters(in: .whitespacesAndNewlines),
            urlPath: urlPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "url" : urlPath,
            headers: headers,
            enabled: enabled,
            isPreset: isPreset
        )
    }

    private static func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let separators: [Character] = [":", "="]
            if let separator = separators.first(where: { line.contains($0) }) {
                let pieces = line.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
                if pieces.count == 2 {
                    let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty, !value.isEmpty {
                        result[key] = value
                    }
                }
            }
        }
        return result
    }
}

private enum ThirdPartySourcePlatform: String, CaseIterable, Identifiable {
    case all
    case netease
    case qq
    case kugou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return beansLocalized("全部平台", "All Platforms")
        case .netease: return beansLocalized("网易云音乐", "NetEase Cloud Music")
        case .qq: return beansLocalized("QQ音乐", "QQ Music")
        case .kugou: return beansLocalized("酷狗音乐", "Kugou Music")
        }
    }

    var code: String? {
        switch self {
        case .all: return nil
        case .netease: return "wy"
        case .qq: return "tx"
        case .kugou: return "kg"
        }
    }

    init(code: String) {
        switch code.lowercased() {
        case "wy", "netease", "cloud":
            self = .netease
        case "tx", "qq", "qqmusic":
            self = .qq
        case "kg", "kugou":
            self = .kugou
        default:
            self = .all
        }
    }
}

private struct SourceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ThirdPartySourceDraft
    let onSave: (ThirdPartySourceDraft) -> Void

    init(draft: ThirdPartySourceDraft, onSave: @escaping (ThirdPartySourceDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    editorCard
                }
                .padding(16)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .background(GlassBackdrop())
            .navigationTitle(beansLocalized("编辑音源", "Edit Source"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(beansLocalized("保存", "Save")) {
                        onSave(draft)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(beansLocalized("取消", "Cancel")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(beansLocalized("音源名称", "Source Name"), text: $draft.name)
                .font(BeansFont.appFont(14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }

            TextField(beansLocalized("类型", "Type"), text: $draft.kind)
                .font(BeansFont.appFont(14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }

            Picker(beansLocalized("适用平台", "Platform"), selection: $draft.platform) {
                ForEach(ThirdPartySourcePlatform.allCases) { platform in
                    Text(platform.title).tag(platform)
                }
            }
            .pickerStyle(.segmented)

            TextField(beansLocalized("URL 模板", "URL Template"), text: $draft.template)
                .font(BeansFont.appFont(14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }

            TextField(beansLocalized("字段路径", "Value Path"), text: $draft.urlPath)
                .font(BeansFont.appFont(14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }

            VStack(alignment: .leading, spacing: 8) {
                Text(beansLocalized("请求头", "Headers"))
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.beansLabel)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft.headersText)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(Color.clear)
                        .modifier(ScrollContentBackgroundHidden())
                    if draft.headersText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(beansLocalized("每行一个 key: value", "One key: value per line"))
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                    }
                }
                .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
            }

            Toggle(isOn: $draft.enabled) {
                Text(beansLocalized("启用", "Enabled"))
                    .font(BeansFont.appFont(14))
                    .foregroundStyle(Color.beansLabel)
            }
            .tint(Color.beansAmber)

            if draft.isPreset {
                Text(beansLocalized("这是预设音源。你可以编辑它，但不能从管理页直接删除。", "This is a preset source. You can edit it, but it cannot be deleted from the manager."))
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
            }
        }
        .padding(16)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 8, y: 3)
    }
}

private struct ScrollContentBackgroundHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

private struct SourceDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .plainText, .item],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: SourceDocumentPicker
        init(_ parent: SourceDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
