import SwiftUI
import CiliCiliKit

struct BilibiliHomePage: View {
    @ObservedObject private var platforms = PlatformPreferenceStore.shared
    @AppStorage("beans.homeSource") private var source = SearchProvider.bilibili.rawValue

    var body: some View {
        CiliCiliHomeView(
            platforms: platforms.enabledSearchProviders.filter { $0 != .qishui }.map(\.rawValue)
        ) { source = $0 }
    }
}

