import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var accessoryStore: SearchBottomAccessoryStore
    @ObservedObject var holder: SearchViewModelHolder

    init(
        holder: SearchViewModelHolder,
        accessoryStore: SearchBottomAccessoryStore
    ) {
        self.holder = holder
        self.accessoryStore = accessoryStore
    }

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                SearchContentView(
                    viewModel: viewModel,
                    showsHotSearches: libraryStore.showsHotSearches,
                    accessoryStore: accessoryStore
                )
            } else {
                SearchLoadingList()
                    .task {
                        holder.configure(api: dependencies.api)
                }
            }
        }
    }
}
