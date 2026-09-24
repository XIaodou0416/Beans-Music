import SwiftUI
import UIKit
import CryptoKit

enum BeansDeveloperAccess {
    // The authorized installation ID is stored as a digest so the raw identifier is not embedded in the app.
    private static let authorizedIdentifierHash = "f6073926d77dd0947338f5f27f133201a484a2d2b28f68f7fbd95cb168526d36"

    static var isAuthorized: Bool {
        let data = Data(DeviceIdentity.userID.lowercased().utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == authorizedIdentifierHash
    }
}

struct DeveloperToolsView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logger = BeansLogger.shared
    @StateObject private var refreshMonitor = BeansRefreshRateMonitor()
    @State private var showLogShare = false
    @State private var showDownloadGrant = false
    @State private var showExclusiveIDGrant = false
    @State private var globalDownloadEnabled = false
    @State private var isLoadingGlobalDownload = false
    @State private var announcementEnabled = false
    @State private var announcementText = ""
    @State private var announcementUpdatedAt = ""
    @State private var isLoadingAnnouncement = false
    @State private var isSavingAnnouncement = false
    @AppStorage("beans.developer.homeFrameMeter") private var homeFrameMeterEnabled = true

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (Build \(build))"
    }

    private var playbackState: String {
        if player.isBuffering { return "缓冲中" }
        if player.loadFailed { return "加载失败" }
        return player.isPlaying ? "播放中" : "已暂停"
    }

    private var progressText: String {
        "\(formatTime(player.progress)) / \(formatTime(player.duration))"
    }

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        refreshCard
                        runtimeCard
                        downloadPermissionCard
                        announcementCard
                        playbackCard
                        diagnosticsCard
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                    .beansAdaptiveContentWidth()
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("开发者工具")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear {
            HighRefreshKeeper.shared.startIfNeeded()
            refreshMonitor.start()
            Task {
                await loadGlobalDownloadStatus()
                await loadAnnouncement()
            }
        }
        .onDisappear { refreshMonitor.stop() }
        .sheet(isPresented: $showLogShare) {
            ShareSheet(items: [BeansLogger.shared.exportLogURL()])
        }
        .sheet(isPresented: $showDownloadGrant) {
            DeveloperDownloadGrantSheet()
                .environmentObject(theme)
        }
        .sheet(isPresented: $showExclusiveIDGrant) {
            DeveloperExclusiveIDSheet()
                .environmentObject(theme)
        }
    }

    private var refreshCard: some View {
        developerCard(title: "显示与刷新率", icon: "gauge.with.dots.needle.67percent", tint: .beansAmber) {
            HStack(spacing: 10) {
                refreshMetric(title: "实时刷新", value: "\(Int(refreshMonitor.framesPerSecond.rounded())) FPS")
                refreshMetric(title: "屏幕上限", value: "\(UIScreen.main.maximumFramesPerSecond) FPS")
            }
            developerRow("界面帧间隔", value: String(format: "%.2f ms", refreshMonitor.frameInterval * 1_000))
            developerRow("低电量模式", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "已开启" : "未开启")
            Toggle("全局显示实时刷新率", isOn: $homeFrameMeterEnabled)
                .font(BeansFont.appFont(13, .medium))
                .tint(Color.beansAmber)
                .onChange(of: homeFrameMeterEnabled) { enabled in
                    DeveloperFPSOverlayWindow.shared.setVisible(enabled)
                }
            if DeviceIdentity.originalPublicID != DeviceIdentity.publicID {
                Button {
                    UIPasteboard.general.string = DeviceIdentity.originalPublicID
                    ToastCenter.shared.show("原始用户 ID 已复制")
                } label: {
                    HStack {
                        Text("原始用户 ID")
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansLabel)
                        Spacer()
                        Text(DeviceIdentity.originalPublicID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.beansAmber)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var runtimeCard: some View {
        developerCard(title: "运行环境", icon: "iphone.gen3", tint: .beansSage) {
            developerRow("设备", value: "\(UIDevice.current.model) · \(DeviceIdentity.hardwareModel)")
            developerRow("系统", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            developerRow("版本", value: appVersion)
            developerRow("界面尺寸", value: "\(Int(UIScreen.main.bounds.width)) × \(Int(UIScreen.main.bounds.height)) @\(String(format: "%.0f", UIScreen.main.scale))x")
            Button {
                UIPasteboard.general.string = DeviceIdentity.publicID
                ToastCenter.shared.show("用户 ID 已复制")
            } label: {
                HStack {
                    Text("用户 ID")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Text(DeviceIdentity.publicID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.beansAmber)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var playbackCard: some View {
        developerCard(title: "播放器状态", icon: "waveform.path.ecg", tint: Color(red: 0.38, green: 0.63, blue: 0.96)) {
            developerRow("状态", value: playbackState)
            developerRow("当前歌曲", value: player.currentSong?.name ?? "无")
            developerRow("播放进度", value: progressText)
            developerRow("队列", value: "\(player.currentIndex + 1) / \(max(player.queue.count, 0))")
            developerRow("播放模式", value: player.playMode.rawValue)
            developerRow("播放速率", value: String(format: "%.2fx", player.rate))
        }
    }

    private var announcementCard: some View {
        developerCard(title: "远程公告", icon: "megaphone", tint: Color.beansHighlight) {
            Toggle("开放公告", isOn: $announcementEnabled)
                .tint(Color.beansAmber)
                .disabled(isLoadingAnnouncement || isSavingAnnouncement)

            TextEditor(text: $announcementText)
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansLabel)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.beansLabel.opacity(0.08), lineWidth: 1)
                        .allowsHitTesting(false)
                }

            HStack(spacing: 10) {
                if !announcementUpdatedAt.isEmpty {
                    Text("更新于 \(announcementUpdatedAt)")
                        .font(BeansFont.appFont(10))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task { await loadAnnouncement() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.beansAmber)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingAnnouncement || isSavingAnnouncement)
                Button {
                    saveAnnouncement()
                } label: {
                    HStack(spacing: 6) {
                        if isSavingAnnouncement {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSavingAnnouncement ? "保存中" : "保存公告")
                    }
                    .font(BeansFont.appFont(12, .semibold))
                    .foregroundStyle(Color.beansLabel)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background { BeansSurface(shape: Capsule()) }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingAnnouncement || isSavingAnnouncement)
            }
        }
    }

    private var downloadPermissionCard: some View {
        developerCard(title: "下载权限", icon: "arrow.down.circle", tint: Color.beansHighlight) {
            Toggle("临时开放所有用户下载", isOn: $globalDownloadEnabled)
                .tint(Color.beansAmber)
                .disabled(isLoadingGlobalDownload)
                .onChange(of: globalDownloadEnabled) { enabled in
                    guard !isLoadingGlobalDownload else { return }
                    Task { await updateGlobalDownloadStatus(enabled) }
                }
            Text("开启后未单独授权的用户也能下载；关闭后只保留此前已经永久授权的用户。")
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
                .fixedSize(horizontal: false, vertical: true)
            Text("使用其他设备的设备标识，为该设备开放或关闭下载功能。")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansComment)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showDownloadGrant = true
            } label: {
                Label("管理其他设备", systemImage: "person.badge.key")
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.beansLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
            }
            .buttonStyle(.plain)
            Button {
                showExclusiveIDGrant = true
            } label: {
                Label("管理专属 ID", systemImage: "crown")
                    .font(BeansFont.appFont(13, .semibold))
                    .foregroundStyle(Color.beansLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
            }
            .buttonStyle(.plain)
        }
    }

    private func loadGlobalDownloadStatus() async {
        guard !isLoadingGlobalDownload else { return }
        isLoadingGlobalDownload = true
        defer { isLoadingGlobalDownload = false }
        do {
            globalDownloadEnabled = try await DeviceReporter.shared.fetchGlobalDownloadAccess()
        } catch {
            BeansLogger.shared.log("临时下载开关读取失败：\(error.localizedDescription)", level: .debug)
        }
    }

    private func updateGlobalDownloadStatus(_ enabled: Bool) async {
        isLoadingGlobalDownload = true
        defer { isLoadingGlobalDownload = false }
        do {
            globalDownloadEnabled = try await DeviceReporter.shared.setGlobalDownloadAccess(enabled)
            ToastCenter.shared.show(enabled ? "已临时开放所有用户下载" : "已恢复永久授权下载")
        } catch {
            globalDownloadEnabled.toggle()
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    private func loadAnnouncement() async {
        guard !isLoadingAnnouncement else { return }
        isLoadingAnnouncement = true
        defer { isLoadingAnnouncement = false }
        do {
            let result = try await DeviceReporter.shared.fetchDeveloperAnnouncement()
            announcementEnabled = result.enabled
            announcementText = result.announcement
            announcementUpdatedAt = result.updatedAt
        } catch {
            BeansLogger.shared.log("开发者公告读取失败：\(error.localizedDescription)", level: .debug)
        }
    }

    private func saveAnnouncement() {
        guard !isSavingAnnouncement else { return }
        isSavingAnnouncement = true
        Task { @MainActor in
            do {
                let result = try await DeviceReporter.shared.updateDeveloperAnnouncement(
                    enabled: announcementEnabled,
                    text: announcementText
                )
                announcementEnabled = result.enabled
                announcementText = result.announcement
                announcementUpdatedAt = result.updatedAt
                await RemoteControlStore.shared.refreshIfNeeded(force: true)
                ToastCenter.shared.show(announcementEnabled ? "公告已开放" : "公告已关闭")
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
            isSavingAnnouncement = false
        }
    }

    private var diagnosticsCard: some View {
        developerCard(title: "诊断与日志", icon: "stethoscope", tint: Color(red: 0.92, green: 0.48, blue: 0.36)) {
            developerRow("内存日志", value: "\(logger.entries.count) 条")
            HStack(spacing: 10) {
                developerAction(title: "记录快照", icon: "camera.viewfinder") {
                    BeansLogger.shared.log(diagnosticSnapshot, level: .info)
                    ToastCenter.shared.show("诊断快照已写入日志")
                }
                developerAction(title: "导出日志", icon: "square.and.arrow.up") {
                    showLogShare = true
                }
            }
        }
    }

    private var diagnosticSnapshot: String {
        "开发者快照：fps=\(Int(refreshMonitor.framesPerSecond.rounded())) maxFPS=\(UIScreen.main.maximumFramesPerSecond) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled) player=\(playbackState) queue=\(player.currentIndex + 1)/\(player.queue.count) progress=\(String(format: "%.2f", player.progress))/\(String(format: "%.2f", player.duration))"
    }

    private func developerCard<Content: View>(title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(BeansFont.appFont(15, .semibold))
                .foregroundStyle(tint)
            content()
        }
        .padding(14)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), forceLiquid: true) }
    }

    private func developerRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(BeansFont.appFont(13))
                .foregroundStyle(Color.beansLabel)
            Spacer(minLength: 12)
            Text(value)
                .font(BeansFont.appFont(12, .medium))
                .foregroundStyle(Color.beansComment)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func refreshMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
            Text(value)
                .font(BeansFont.appFont(22, .bold))
                .foregroundStyle(Color.beansLabel)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func developerAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BeansFont.appFont(13, .semibold))
                .foregroundStyle(Color.beansLabel)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct DeveloperDownloadGrantSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var targetDeviceID = ""
    @State private var enabled = true
    @State private var isSubmitting = false
    @State private var isLoadingRecords = false
    @State private var accessRecords: [BeansDownloadAccessRecord] = []
    @State private var errorMessage = ""

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("下载权限")
                            .font(BeansFont.appFont(24, .bold))
                            .foregroundStyle(Color.beansLabel)
                        Text("输入对方的设备码。对方需要先启动过 Beans，才能被找到并更新权限。")
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansComment)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("设备码", text: $targetDeviceID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), forceLiquid: true) }
                        Toggle("开放下载功能", isOn: $enabled)
                            .tint(Color.beansAmber)
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(BeansFont.appFont(12, .medium))
                                .foregroundStyle(.red)
                        }
                        Button {
                            submit()
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting { ProgressView().tint(Color.beansLabel) }
                                Text(isSubmitting ? "正在保存" : "保存权限")
                            }
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting || !isValidTargetID)
                        accessRecordsSection
                    }
                    .padding(20)
                    .beansAdaptiveContentWidth()
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("开发者权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            await reloadRecords()
        }
    }

    private var accessRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("授权记录")
                    .font(BeansFont.appFont(16, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                if isLoadingRecords {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await reloadRecords() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新授权记录")
                }
            }

            if latestRecords.isEmpty && !isLoadingRecords {
                Text("暂无下载权限记录")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            } else {
                ForEach(latestRecords) { record in
                    downloadAccessRow(record)
                }
            }
        }
        .padding(14)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), forceLiquid: true) }
    }

    private var latestRecords: [BeansDownloadAccessRecord] {
        var seen = Set<String>()
        return accessRecords.filter { seen.insert($0.userID).inserted }.prefix(50).map { $0 }
    }

    private func downloadAccessRow(_ record: BeansDownloadAccessRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.deviceName.isEmpty ? record.deviceModel : record.deviceName)
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(Color.beansLabel)
                    Text("设备码 \(record.userID) · 显示 ID \(record.publicUserID ?? "未设置") · \(record.systemName) \(record.systemVersion)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(record.enabled ? "已开放" : "已取消")
                    .font(BeansFont.appFont(11, .semibold))
                    .foregroundStyle(record.enabled ? Color.beansSage : Color.beansComment)
            }
            HStack {
                Text(record.changedAt.isEmpty ? "" : "最后操作：\(record.changedAt)")
                    .font(BeansFont.appFont(10))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
                Spacer()
                Button {
                    targetDeviceID = record.userID
                    enabled = !record.enabled
                    submit()
                } label: {
                    Text(record.enabled ? "取消权限" : "重新开放")
                        .font(BeansFont.appFont(11, .semibold))
                        .foregroundStyle(record.enabled ? .red : Color.beansAmber)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = ""
        Task { @MainActor in
            do {
                try await DeviceReporter.shared.grantDownloadAccess(to: targetDeviceID, enabled: enabled)
                ToastCenter.shared.show(enabled ? "已开放该设备的下载功能" : "已关闭该设备的下载功能")
                // The permission mutation can succeed even when the follow-up
                // history refresh loses its response. Do not turn that refresh
                // failure into a false failure message for the completed action.
                await reloadRecords(showError: false)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private var isValidTargetID: Bool {
        let value = targetDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"^[a-f0-9-]{16,80}$"#, options: .regularExpression) != nil
    }

    private func reloadRecords(showError: Bool = true) async {
        guard !isLoadingRecords else { return }
        isLoadingRecords = true
        defer { isLoadingRecords = false }
        do {
            accessRecords = try await DeviceReporter.shared.fetchDownloadAccessRecords()
        } catch {
            if showError && accessRecords.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                BeansLogger.shared.log("下载权限记录刷新失败：\(error.localizedDescription)", level: .debug)
            }
        }
    }
}

private struct DeveloperExclusiveIDSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var targetUserID = ""
    @State private var assignedPublicID = ""
    @State private var enabled = true
    @State private var badgeStyle: BeansExclusiveIDBadgeStyle = .blackPurpleGold
    @State private var isSubmitting = false
    @State private var isLoadingRecords = false
    @State private var records: [BeansExclusiveAccessRecord] = []
    @State private var errorMessage = ""

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("专属 ID")
                            .font(BeansFont.appFont(24, .bold))
                            .foregroundStyle(Color.beansLabel)
                        Text("输入对方的设备码，再设置公开显示 ID。公开 ID 可以与其他用户重复。")
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansComment)
                            .fixedSize(horizontal: false, vertical: true)
                        inputField(
                            "目标设备码",
                            placeholder: "粘贴设备码",
                            detail: "用于定位设备，不会修改设备码。",
                            text: $targetUserID
                        )
                        HStack {
                            Spacer()
                            Button("编辑当前设备") {
                                targetUserID = DeviceIdentity.userID
                            }
                            .font(BeansFont.appFont(12, .semibold))
                            .foregroundStyle(Color.beansAmber)
                            .buttonStyle(.plain)
                        }
                        inputField(
                            "公开显示 ID",
                            placeholder: "支持中文，最多 24 个字符",
                            detail: "中文也会显示在 ID 铭牌中，不影响昵称；留空保留当前 ID。",
                            text: $assignedPublicID,
                            isPublicID: true
                        )
                        badgeStyleSelector
                        Toggle("启用专属铭牌", isOn: $enabled)
                            .tint(Color.beansAmber)
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(BeansFont.appFont(12, .medium))
                                .foregroundStyle(.red)
                        }
                        Button(action: submit) {
                            HStack(spacing: 8) {
                                if isSubmitting { ProgressView().tint(Color.beansLabel) }
                                Text(isSubmitting ? "正在保存" : "保存专属 ID")
                            }
                            .font(BeansFont.appFont(14, .semibold))
                            .foregroundStyle(Color.beansLabel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background { BeansGlass(shape: Capsule(), forceLiquid: true) }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting || !isValidTargetID || !isValidAssignedID)
                        recordsSection
                    }
                    .padding(20)
                    .beansAdaptiveContentWidth()
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("开发者权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await reloadRecords() }
    }

    private func inputField(
        _ title: String,
        placeholder: String,
        detail: String,
        text: Binding<String>,
        isPublicID: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BeansFont.appFont(13, .semibold))
                .foregroundStyle(Color.beansLabel)
            Text(detail)
                .font(BeansFont.appFont(11))
                .foregroundStyle(Color.beansComment)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(isPublicID ? BeansFont.appFont(14) : .system(size: 13, design: .monospaced))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), forceLiquid: true) }
        }
    }

    private var badgeStyleSelector: some View {
        HStack(spacing: 8) {
            ForEach(BeansExclusiveIDBadgeStyle.allCases, id: \.self) { style in
                Button {
                    guard badgeStyle != style else { return }
                    BeansHaptics.tap()
                    badgeStyle = style
                } label: {
                    Text(style.displayName)
                        .font(BeansFont.appFont(13, .semibold))
                        .foregroundStyle(badgeStyle == style ? Color.beansLabel : Color.beansComment)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if badgeStyle == style {
                                BeansGlass(shape: Capsule(), forceLiquid: true)
                            } else {
                                Capsule().fill(Color.beansLabel.opacity(0.06))
                            }
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    badgeStyle == style ? Color.beansAmber.opacity(0.72) : Color.clear,
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
            }
        }
        .padding(4)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), forceLiquid: true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("专属铭牌样式")
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("专属 ID 记录")
                    .font(BeansFont.appFont(16, .semibold))
                    .foregroundStyle(Color.beansLabel)
                Spacer()
                if isLoadingRecords {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await reloadRecords() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.beansAmber)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }

            if records.isEmpty && !isLoadingRecords {
                Text("暂无专属 ID 记录")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            } else {
                ForEach(records.prefix(50)) { record in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.deviceName.isEmpty ? record.deviceModel : record.deviceName)
                                    .font(BeansFont.appFont(13, .semibold))
                                    .foregroundStyle(Color.beansLabel)
                                Text("用户 ID \(record.publicUserID ?? record.userID) · \(record.badgeStyle?.displayName ?? BeansExclusiveIDBadgeStyle.blackPurpleGold.displayName)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color.beansComment)
                            }
                            Spacer(minLength: 8)
                            Text(record.enabled ? "已授权" : "已取消")
                                .font(BeansFont.appFont(11, .semibold))
                                .foregroundStyle(record.enabled ? Color.beansAmber : Color.beansComment)
                        }
                        HStack {
                            Text(record.changedAt.isEmpty ? "" : "最后操作：\(record.changedAt)")
                                .font(BeansFont.appFont(10))
                                .foregroundStyle(Color.beansComment)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                targetUserID = record.userID
                                assignedPublicID = ""
                                enabled = !record.enabled
                                badgeStyle = record.badgeStyle ?? .blackPurpleGold
                                submit()
                            } label: {
                                Text(record.enabled ? "取消专属" : "恢复专属")
                                    .font(BeansFont.appFont(11, .semibold))
                                    .foregroundStyle(record.enabled ? .red : Color.beansAmber)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), forceLiquid: true) }
    }

    private var isValidTargetID: Bool {
        let value = targetUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.range(of: #"^[a-f0-9-]{16,80}$"#, options: .regularExpression) != nil
    }

    private var isValidAssignedID: Bool {
        let value = assignedPublicID.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || DeviceIdentity.isValidPublicID(value)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = ""
        Task { @MainActor in
            do {
                try await DeviceReporter.shared.grantExclusiveID(
                    to: targetUserID,
                    assignedPublicID: assignedPublicID,
                    enabled: enabled,
                    badgeStyle: badgeStyle
                )
                ToastCenter.shared.show(enabled ? "已授权专属 ID" : "已取消专属 ID")
                applyOptimisticRecordState()
                isSubmitting = false
                Task { await reloadRecords(showError: false) }
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func applyOptimisticRecordState() {
        let target = targetUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let index = records.firstIndex(where: {
            $0.userID.lowercased() == target || $0.publicUserID?.lowercased() == target
        }) else { return }
        let current = records[index]
        records[index] = BeansExclusiveAccessRecord(
            userID: current.userID,
            publicUserID: assignedPublicID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? current.publicUserID
                : assignedPublicID.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceModel: current.deviceModel,
            deviceName: current.deviceName,
            systemName: current.systemName,
            systemVersion: current.systemVersion,
            appVersion: current.appVersion,
            appBuild: current.appBuild,
            lastSeenAt: current.lastSeenAt,
            enabled: enabled,
            badgeStyle: badgeStyle,
            changedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func reloadRecords(showError: Bool = true) async {
        guard !isLoadingRecords else { return }
        isLoadingRecords = true
        defer { isLoadingRecords = false }
        do {
            records = try await DeviceReporter.shared.fetchExclusiveAccessRecords()
        } catch {
            if showError && records.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                BeansLogger.shared.log("专属 ID 记录刷新失败：\(error.localizedDescription)", level: .debug)
            }
        }
    }
}

private struct DeveloperFrameRateOverlay: View {
    @StateObject private var monitor = BeansRefreshRateMonitor()
    @AppStorage("beans.developer.fpsOverlay.x") private var storedX = -1.0
    @AppStorage("beans.developer.fpsOverlay.y") private var storedY = -1.0
    @State private var displayPosition: CGPoint?
    @State private var dragOrigin: CGPoint?

    private let badgeSize = CGSize(width: 84, height: 28)

    var body: some View {
        GeometryReader { proxy in
            let currentPosition = resolvedPosition(in: proxy)

            Text("\(Int(monitor.framesPerSecond.rounded())) FPS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: badgeSize.width, height: badgeSize.height)
                .background(.thinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.8) }
                .accessibilityIdentifier("beans.developer.fpsBadge")
                .position(currentPosition)
                .gesture(dragGesture(in: proxy, currentPosition: currentPosition))
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func resolvedPosition(in proxy: GeometryProxy) -> CGPoint {
        let fallback = CGPoint(
            x: proxy.size.width - badgeSize.width / 2 - 14,
            y: max(proxy.safeAreaInsets.top, 10) + badgeSize.height / 2
        )
        let persisted = storedX >= 0 && storedY >= 0
            ? CGPoint(x: storedX * proxy.size.width, y: storedY * proxy.size.height)
            : fallback
        return clamped(displayPosition ?? persisted, in: proxy)
    }

    private func clamped(_ point: CGPoint, in proxy: GeometryProxy) -> CGPoint {
        let horizontalInset = badgeSize.width / 2 + 8
        let topInset = max(proxy.safeAreaInsets.top, 8) + badgeSize.height / 2
        let bottomInset = max(proxy.safeAreaInsets.bottom, 8) + badgeSize.height / 2
        return CGPoint(
            x: min(max(point.x, horizontalInset), max(horizontalInset, proxy.size.width - horizontalInset)),
            y: min(max(point.y, topInset), max(topInset, proxy.size.height - bottomInset))
        )
    }

    private func dragGesture(in proxy: GeometryProxy, currentPosition: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = currentPosition
                }
                guard let dragOrigin else { return }
                displayPosition = clamped(
                    CGPoint(
                        x: dragOrigin.x + value.translation.width,
                        y: dragOrigin.y + value.translation.height
                    ),
                    in: proxy
                )
            }
            .onEnded { _ in
                let finalPosition = clamped(displayPosition ?? currentPosition, in: proxy)
                storedX = Double(finalPosition.x / max(proxy.size.width, 1))
                storedY = Double(finalPosition.y / max(proxy.size.height, 1))
                displayPosition = finalPosition
                dragOrigin = nil
            }
    }
}

/// 开发者设备上的独立浮层窗口，覆盖 Tab、sheet 和全屏播放器，保证帧率读数来自当前全局渲染循环。
@MainActor
final class DeveloperFPSOverlayWindow {
    static let shared = DeveloperFPSOverlayWindow()

    private var window: DeveloperFPSPassthroughWindow?

    func setVisible(_ requested: Bool) {
        guard requested, BeansDeveloperAccess.isAuthorized else {
            window?.isHidden = true
            window = nil
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            // The root view can appear one run loop before the scene becomes
            // active. Retry once so the global meter does not silently vanish.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                self.setVisible(requested)
            }
            return
        }

        if window?.windowScene !== scene {
            window?.isHidden = true
            window = nil
        }
        if window == nil {
            let overlayWindow = DeveloperFPSPassthroughWindow(windowScene: scene)
            let controller = UIHostingController(rootView: DeveloperFrameRateOverlay())
            controller.view.backgroundColor = .clear
            controller.view.isUserInteractionEnabled = true
            overlayWindow.rootViewController = controller
            overlayWindow.backgroundColor = .clear
            overlayWindow.isUserInteractionEnabled = true
            overlayWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1)
            window = overlayWindow
        }
        HighRefreshKeeper.shared.startIfNeeded()
        window?.isHidden = false
    }
}

/// Only the badge accepts touches, so the rest of the app keeps its normal gestures.
@MainActor
private final class DeveloperFPSPassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        var view: UIView? = hitView
        while let current = view {
            if current.accessibilityIdentifier == "beans.developer.fpsBadge" {
                return hitView
            }
            view = current.superview
        }
        return nil
    }
}

@MainActor
final class BeansRefreshRateMonitor: NSObject, ObservableObject {
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var frameInterval: TimeInterval = 0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frameCount = 0

    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        windowStart = 0
        frameCount = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Follow the panel maximum so ProMotion is sampled above 60 Hz.
        let maximum = min(120, max(60, UIScreen.main.maximumFramesPerSecond))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(maximum >= 120 ? 60 : maximum),
            maximum: Float(maximum),
            preferred: Float(maximum)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func restart() {
        stop()
        start()
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        if lastTimestamp > 0 {
            frameInterval = displayLink.timestamp - lastTimestamp
        }
        lastTimestamp = displayLink.timestamp
        if windowStart == 0 { windowStart = displayLink.timestamp }
        frameCount += 1
        let elapsed = displayLink.timestamp - windowStart
        if elapsed >= 0.75 {
            framesPerSecond = Double(frameCount) / elapsed
            frameCount = 0
            windowStart = displayLink.timestamp
        }
    }

    deinit { displayLink?.invalidate() }
}

