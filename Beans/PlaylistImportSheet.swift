import SwiftUI
import UniformTypeIdentifiers

/// Moumusic-style local playlist import UI, adapted to Beans' sheet/navigation components.
struct PlaylistImportSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = LocalLibraryStore.shared
    @State private var input = ""
    @State private var isImporting = false
    @State private var showFileImporter = false
    @State private var errorMessage: String?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                Form {
                    Section("粘贴歌单") {
                        TextEditor(text: $input)
                            .frame(minHeight: 180)
                            .font(BeansFont.appFont(15))
                            .overlay(alignment: .topLeading) {
                                if input.isEmpty {
                                    Text("粘贴网易云公开歌单链接，或粘贴其他音乐软件导出的歌单 JSON。网易云歌曲仍由已选音源负责播放。")
                                        .font(BeansFont.appFont(14))
                                        .foregroundStyle(Color.beansComment)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    Section {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("选择 JSON / 文本文件", systemImage: "doc.badge.plus")
                        }
                        .frame(minHeight: 44)

                        Button {
                            importPlaylist()
                        } label: {
                            HStack {
                                Text(isImporting ? "正在导入…" : "开始导入")
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                        .tint(Color.beansAmber)
                                }
                            }
                        }
                        .disabled(isImporting || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(minHeight: 44)
                    }

                    Section("说明") {
                        Text("歌单只保存到本机，不会修改原音乐软件。支持网易云公开歌单链接和 JSON；在线目录只读取公开信息，实际播放仍使用 Beans 已启用的音源。")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                    }
                }
                .modifier(GroupedFormStyleCompatibility())
                .beansScrollContentBackgroundHidden()
            }
            .navigationTitle("导入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    input = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    errorMessage = "读取文件失败：\(error.localizedDescription)"
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
        .onDisappear {
            importTask?.cancel()
        }
    }

    private func importPlaylist() {
        let value = input
        isImporting = true
        errorMessage = nil
        importTask?.cancel()
        importTask = Task { @MainActor in
            do {
                _ = try await store.importPlaylist(from: value)
                guard !Task.isCancelled else { return }
                isImporting = false
                BeansHaptics.success()
                ToastCenter.shared.show("歌单已导入到本地音乐库")
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct GroupedFormStyleCompatibility: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}
