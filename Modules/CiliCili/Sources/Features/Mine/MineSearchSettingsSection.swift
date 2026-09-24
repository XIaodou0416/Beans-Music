import SwiftUI

struct MineSearchSettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("搜索") {
            Toggle(isOn: Binding(
                get: { libraryStore.showsHotSearches },
                set: { libraryStore.setShowsHotSearches($0) }
            )) {
                MineSettingsLabel("显示热门搜索", systemImage: "flame")
            }
        }
    }
}
