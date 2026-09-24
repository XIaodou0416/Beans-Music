import SwiftUI

struct ResourceCacheManagementView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage(ResourceCacheLimitSettings.isEnabledKey) private var isCacheLimitEnabled = ResourceCacheLimitSettings.defaultIsEnabled
    @AppStorage(ResourceCacheLimitSettings.megabytesKey) private var cacheLimitMegabytes = ResourceCacheLimitSettings.defaultLimitMegabytes
    @State private var summary: ResourceCacheSummary?
    @State private var isWorking = false

    var body: some View {
        List {
            ResourceCacheSummarySection(
                summary: summary,
                cacheLimitSubtitle: cacheLimitSubtitle
            )

            ResourceCacheLimitSection(
                isCacheLimitEnabled: $isCacheLimitEnabled,
                cacheLimitMegabytes: cacheLimitBinding,
                applyLimit: applyCacheLimitNow
            )

            ResourceCacheCleanupSection(performClear: performClear)
        }
        .tint(libraryStore.appTintColor)
        .listStyle(.insetGrouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .disabled(isWorking)
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
        .onChange(of: isCacheLimitEnabled) { _, _ in
            scheduleCacheLimitApply()
        }
        .onChange(of: cacheLimitMegabytes) { _, value in
            let clamped = ResourceCacheLimitSettings.clampedMegabytes(value)
            if clamped != value {
                cacheLimitMegabytes = clamped
            }
            scheduleCacheLimitApply()
        }
    }

    private var cacheLimitBinding: Binding<Int> {
        Binding(
            get: { ResourceCacheLimitSettings.normalizedLimitMegabytes(cacheLimitMegabytes) },
            set: { cacheLimitMegabytes = ResourceCacheLimitSettings.normalizedLimitMegabytes($0) }
        )
    }

    private var cacheLimitSubtitle: String {
        isCacheLimitEnabled
            ? "上限 \(ResourceCacheByteFormatter.megabytes(ResourceCacheLimitSettings.clampedMegabytes(cacheLimitMegabytes)))"
            : "未启用自动上限"
    }

    private func performClear(_ operation: @escaping () async -> Void) {
        Task {
            isWorking = true
            await operation()
            await reload()
            isWorking = false
        }
    }

    private func reload() async {
        summary = await ResourceCacheCenter.summary()
    }

    private func scheduleCacheLimitApply() {
        Task {
            if isCacheLimitEnabled {
                isWorking = true
                await ResourceCacheCenter.enforceConfiguredLimit()
                isWorking = false
            }
            await reload()
        }
    }

    private func applyCacheLimitNow() {
        performClear {
            await ResourceCacheCenter.enforceConfiguredLimit()
        }
    }
}
