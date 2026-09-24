import SwiftUI

struct FavoriteFolderSelectionToolbar: ToolbarContent {
    let canSave: Bool
    let cancel: () -> Void
    let save: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消", action: cancel)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("保存", action: save)
                .disabled(!canSave)
        }
    }
}
