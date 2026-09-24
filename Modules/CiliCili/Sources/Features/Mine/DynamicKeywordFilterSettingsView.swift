import SwiftUI

struct DynamicKeywordFilterSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var draftKeyword = ""
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("输入关键词", text: $draftKeyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isDraftFocused)
                    .submitLabel(.done)
                    .onSubmit(addKeyword)

                Button {
                    addKeyword()
                } label: {
                    MineSettingsLabel("添加关键词", systemImage: "plus.circle")
                }
                .disabled(normalizedDraftKeyword == nil)
            } header: {
                Text("添加关键词")
            } footer: {
                Text("命中任意关键词的动态会自动隐藏。关键词会匹配正文、标题、视频标题和转发内容。")
            }

            Section {
                if libraryStore.blockedDynamicKeywords.isEmpty {
                    Text("还没有添加关键词")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(libraryStore.blockedDynamicKeywords.enumerated()), id: \.offset) { _, keyword in
                        HStack(spacing: 10) {
                            Text(keyword)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Button(role: .destructive) {
                                libraryStore.removeBlockedDynamicKeyword(keyword)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除 \(keyword)")
                        }
                    }

                    if !libraryStore.blockedDynamicKeywords.isEmpty {
                        Button(role: .destructive) {
                            libraryStore.clearBlockedDynamicKeywords()
                        } label: {
                            MineSettingsLabel("清空全部", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("已屏蔽关键词")
            }
        }
        .tint(libraryStore.appTintColor)
        .listStyle(.insetGrouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }

    private var normalizedDraftKeyword: String? {
        let keyword = draftKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyword.isEmpty ? nil : keyword
    }

    private func addKeyword() {
        guard let keyword = normalizedDraftKeyword else { return }
        libraryStore.addBlockedDynamicKeyword(keyword)
        draftKeyword = ""
        isDraftFocused = true
    }
}
