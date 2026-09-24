import SwiftUI

struct FavoriteFolderSelectionLoadedSection: View {
    let folders: [FavoriteFolder]
    @Binding var selectedFolderIDs: Set<Int>

    var body: some View {
        Section {
            ForEach(folders) { folder in
                Toggle(isOn: selectionBinding(for: folder)) {
                    FavoriteFolderSelectionRow(folder: folder)
                }
                .toggleStyle(.switch)
            }
        } footer: {
            Text("可同时收藏到多个文件夹；关闭所有开关会取消收藏。")
        }
    }

    private func selectionBinding(for folder: FavoriteFolder) -> Binding<Bool> {
        Binding(
            get: { selectedFolderIDs.contains(folder.id) },
            set: { isSelected in
                if isSelected {
                    selectedFolderIDs.insert(folder.id)
                } else {
                    selectedFolderIDs.remove(folder.id)
                }
            }
        )
    }
}

private struct FavoriteFolderSelectionRow: View {
    let folder: FavoriteFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(folder.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\(folder.mediaCount ?? 0) 个内容")
                if folder.isFavorited {
                    Text("当前已收藏")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
