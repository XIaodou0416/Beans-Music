import SwiftUI

struct MineDisplaySettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage(VideoCoverBadgeContrastBacking.storageKey) private var videoCoverBadgeContrastBackingOpacity = VideoCoverBadgeContrastBacking.defaultOpacity

    var body: some View {
        Section("显示") {
            Text("应用外观、图标和底栏由 Beans 的设置统一管理。")
                .font(.footnote).foregroundStyle(.secondary)

            MineThemeColorControl(libraryStore: libraryStore)

            Toggle(isOn: Binding(
                get: { libraryStore.followsSystemFontSize },
                set: { libraryStore.setFollowsSystemFontSize($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("字体跟随系统字号", systemImage: "textformat.size")

                    Text("关闭后可以固定 App 字号，不再随系统文字大小变化。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !libraryStore.followsSystemFontSize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        MineSettingsLabel("手动字体大小", systemImage: "textformat")
                        Spacer(minLength: 8)
                        Text(libraryStore.manualFontSize.title)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: manualFontSizeBinding,
                        in: 0...Double(AppManualFontSize.allCases.count - 1),
                        step: 1
                    ) {
                        Text("手动字体大小")
                    } minimumValueLabel: {
                        Text("A").font(.caption2)
                    } maximumValueLabel: {
                        Text("A").font(.title3)
                    }
                    .tint(libraryStore.appTintColor)
                    .accessibilityValue(libraryStore.manualFontSize.title)
                }
            }

            Picker(selection: Binding(
                get: { libraryStore.remoteImageQualityPreference },
                set: { libraryStore.setRemoteImageQualityPreference($0) }
            )) {
                ForEach(RemoteImageQualityPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("图片质量", systemImage: "photo")

                    Text(libraryStore.remoteImageQualityPreference.detail)
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .pickerStyle(.menu)

            MineImageCacheControl()

            Toggle(isOn: Binding(
                get: { libraryStore.showsVideoCoverDurationBadges },
                set: { libraryStore.setShowsVideoCoverDurationBadges($0) }
            )) {
                MineSettingsLabel("显示视频封面时长", systemImage: "timer")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.remoteImageDiagnosticsEnabled },
                set: { libraryStore.setRemoteImageDiagnosticsEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("记录图片加载诊断", systemImage: "chart.bar.xaxis")

                    Text("开着会记缓存、滚动和 CDN 的汇总数字，方便复制给我分析；不记图片、链接、账号或 Cookie。关掉后不再记数，图片照常加载。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            NavigationLink {
                RemoteImageDiagnosticsView(libraryStore: libraryStore)
            } label: {
                MineSettingsLabel("图片加载诊断", systemImage: "chart.bar.xaxis")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MineSettingsLabel("封面角标暗色底", systemImage: "circle.lefthalf.filled")
                    Spacer(minLength: 8)
                    Text(videoCoverBadgeContrastBackingOpacityTitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: {
                            VideoCoverBadgeContrastBacking.normalized(videoCoverBadgeContrastBackingOpacity)
                        },
                        set: { value in
                            videoCoverBadgeContrastBackingOpacity = VideoCoverBadgeContrastBacking.normalized(value)
                        }
                    ),
                    in: VideoCoverBadgeContrastBacking.opacityRange,
                    step: 0.05
                )
            }
            .disabled(!libraryStore.showsVideoCoverDurationBadges)

            Picker(selection: Binding(
                get: { libraryStore.videoDetailSegmentedPickerGlassStyle },
                set: { libraryStore.setVideoDetailSegmentedPickerGlassStyle($0) }
            )) {
                ForEach(VideoDetailSegmentedPickerGlassStyle.allCases) { glassStyle in
                    Text(glassStyle.title).tag(glassStyle)
                }
            } label: {
                MineSettingsLabel("底部栏液态玻璃效果", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)

            Toggle(isOn: Binding(
                get: { libraryStore.force120HzScrollingEnabled },
                set: { libraryStore.setForce120HzScrollingEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("强制滑动 120Hz 刷新率", systemImage: "speedometer")

                    Text("开启后滑动会强制使用 120Hz，可能会引起耗电增加，请谨慎开启。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        Section("实验功能") {
            Toggle(isOn: Binding(
                get: { libraryStore.dynamicCommentHitAreaVisualizationExperimentEnabled },
                set: { libraryStore.setDynamicCommentHitAreaVisualizationExperimentEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("动态评论点击区域可视化", systemImage: "hand.tap")

                    Text("用半透明色块标示动态详情和评论弹窗中的回复与独立操作区域。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
    }

    private var videoCoverBadgeContrastBackingOpacityTitle: String {
        "\(Int((VideoCoverBadgeContrastBacking.normalized(videoCoverBadgeContrastBackingOpacity) * 100).rounded()))%"
    }

    private var manualFontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(libraryStore.manualFontSize.rawValue) },
            set: { value in
                guard let size = AppManualFontSize(rawValue: Int(value.rounded())) else { return }
                libraryStore.setManualFontSize(size)
            }
        )
    }
}

private struct MineThemeColorControl: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var selectionMode: ThemeColorSelectionMode = .tone
    @State private var tintHexDraft = ""

    private let swatchHexes = AppThemeTintColor.toneHexes
    private let swatchColumns = Array(repeating: GridItem(.fixed(32), spacing: 12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MineSettingsLabel("主色调", systemImage: "paintpalette")

            Picker("选择方式", selection: $selectionMode) {
                ForEach(ThemeColorSelectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            selectedModeContent

            currentSelectionFooter

            Text("影响 App 选中状态、系统控件高亮和首页点击刷新颜色。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            tintHexDraft = libraryStore.appTintColorHex
            selectionMode = mode(for: libraryStore.appTintColorHex)
        }
        .onChange(of: libraryStore.appTintColorHex) { _, hex in
            tintHexDraft = hex
        }
        .tint(libraryStore.appTintColor)
    }

    @ViewBuilder
    private var selectedModeContent: some View {
        switch selectionMode {
        case .tone:
            LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: 12) {
                ForEach(swatchHexes, id: \.self) { hex in
                    Button {
                        libraryStore.setAppTintColorHex(hex)
                        tintHexDraft = libraryStore.appTintColorHex
                    } label: {
                        colorSwatch(hex)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择颜色 \(hex)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .palette:
            VStack(alignment: .leading, spacing: 10) {
                ColorPicker(
                    selection: Binding(
                        get: { libraryStore.appTintColor },
                        set: { color in
                            libraryStore.setAppTintColor(color)
                            tintHexDraft = libraryStore.appTintColorHex
                        }
                    ),
                    supportsOpacity: false
                ) {
                        MineSettingsLabel("直接从色板选", systemImage: "eyedropper")
                }

                HStack(spacing: 10) {
                    TextField(AppThemeTintColor.defaultHex, text: $tintHexDraft)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit(commitDraftHex)

                    Button {
                        commitDraftHex()
                    } label: {
                        MineSettingsLabel("应用", systemImage: "checkmark.circle")
                    }
                    .disabled(normalizedDraftHex == nil)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var currentSelectionFooter: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(libraryStore.appTintColor)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(Color(.separator).opacity(0.30), lineWidth: 0.8)
                }

            Text(libraryStore.appTintColorHex)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button("恢复默认") {
                libraryStore.resetAppTintColor()
                tintHexDraft = libraryStore.appTintColorHex
                selectionMode = .tone
            }
            .buttonStyle(.borderless)
        }
    }

    private var normalizedDraftHex: String? {
        AppThemeTintColor.normalizedHex(tintHexDraft)
    }

    private func commitDraftHex() {
        guard let normalizedDraftHex else { return }
        libraryStore.setAppTintColorHex(normalizedDraftHex)
        tintHexDraft = libraryStore.appTintColorHex
    }

    private func mode(for hex: String) -> ThemeColorSelectionMode {
        swatchHexes.contains(hex) ? .tone : .palette
    }

    private func colorSwatch(_ hex: String) -> some View {
        let color = AppThemeTintColor.color(for: hex)
        let isSelected = libraryStore.appTintColorHex == hex
        return Circle()
            .fill(color)
            .frame(width: 24, height: 24)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                Circle()
                    .stroke(Color(.separator).opacity(0.30), lineWidth: 0.8)
            }
    }
}

private struct MineImageCacheControl: View {
    @State private var statistics: RemoteImageCacheStatistics?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MineSettingsLabel("图片缓存", systemImage: "photo.on.rectangle")

                Spacer(minLength: 8)

                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(summaryTitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(summaryDetail)
                .appTypography(.settingsSubtitle, fallback: .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive) {
                Task {
                    await clearImageCache()
                }
            } label: {
                MineSettingsLabel("清理图片缓存", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(isWorking)
        }
        .task {
            await reload()
        }
    }

    private var summaryTitle: String {
        guard let statistics else { return "读取中" }
        return ResourceCacheByteFormatter.bytes(statistics.diskUsage)
    }

    private var summaryDetail: String {
        guard let statistics else {
            return "正在读取内存和磁盘图片缓存。"
        }
        return "\(statistics.memoryEntryCount) 张 · 磁盘 \(ResourceCacheByteFormatter.bytes(statistics.diskUsage)) / \(ResourceCacheByteFormatter.bytes(statistics.diskCapacity))"
    }

    @MainActor
    private func reload() async {
        statistics = await RemoteImageCache.shared.statistics()
    }

    @MainActor
    private func clearImageCache() async {
        isWorking = true
        await ResourceCacheCenter.clearImages(includeDisk: true)
        await reload()
        isWorking = false
    }
}

private enum ThemeColorSelectionMode: String, CaseIterable, Identifiable {
    case tone
    case palette

    var id: Self { self }

    var title: String {
        switch self {
        case .tone:
            "色调"
        case .palette:
            "色板"
        }
    }
}
