import SwiftUI

enum QRStatus: Equatable {
    case loading
    case waiting
    case scanned
    case success
    case expired
    case error(String)
}

struct LoginView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore

    @State private var key: String?
    @State private var status: QRStatus = .loading
    @State private var timer: Timer?
    @State private var showWebLogin = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = theme.accent
        ZStack {
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "beats.headphones")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(LinearGradient.beansAccent)
                Text("Beans Music")
                    .font(BeansFont.appFont(34, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text("登录网易云音乐，同步你的歌单")
                    .font(BeansFont.appFont(14))
                    .foregroundStyle(Color.beansComment)

                qrArea
                    .frame(width: 250, height: 250)
                    .padding(18)
                    .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 30, style: .continuous)) }
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)

                statusView

                Button {
                    BeansHaptics.tap()
                    showWebLogin = true
                } label: {
                    Label("网页登录", systemImage: "globe")
                        .font(BeansFont.appFont(13, .medium))
                        .foregroundStyle(Color.beansAmber)
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.94))

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear { startLogin() }
        .onDisappear { timer?.invalidate() }
        .sheet(isPresented: $showWebLogin) {
            BeansNavigationStack {
                NetEaseWebLoginPanel {
                    dismiss()
                }
                .environmentObject(auth)
                .environmentObject(theme)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showWebLogin = false }
                    }
                }
            }
            .modifier(BeansSheetModifier(detents: [.large]))
        }
    }

    @ViewBuilder
    private var qrArea: some View {
        ZStack {
            if let key {
                QRCodeView(text: NetEaseAPI.shared.qrLoginURL(key: key))
            } else {
                ProgressView().tint(Color.beansAmber)
            }
            if status == .expired || isError {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 34))
                    Text(isError ? errorText : "二维码已过期")
                        .font(BeansFont.appFont(13))
                    GlassButton(title: "刷新", systemName: "arrow.clockwise", prominent: true) {
                        startLogin()
                    }
                }
                .foregroundStyle(Color.beansLabel)
                .frame(width: 210, height: 210)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var statusView: some View {
        Group {
            switch status {
            case .loading:
                Text("正在生成二维码…")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            case .waiting:
                Label("请使用网易云音乐 App 扫码", systemImage: "qrcode.viewfinder")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            case .scanned:
                Label("已扫码，请在手机上确认登录", systemImage: "checkmark.circle")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansSage)
            case .success:
                Label("登录成功，正在同步歌单…", systemImage: "checkmark.seal.fill")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansSage)
            case .expired:
                Text("二维码已过期")
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.beansComment)
            case .error(let message):
                Text(message)
                    .font(BeansFont.appFont(13))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(height: 44)
    }

    private var isError: Bool {
        if case .error = status { return true }
        return false
    }

    private var errorText: String {
        if case .error(let message) = status { return message }
        return ""
    }

    // MARK: - 登录流程

    private func startLogin() {
        timer?.invalidate()
        timer = nil
        status = .loading
        Task {
            do {
                let newKey = try await NetEaseAPI.shared.qrKey()
                await MainActor.run {
                    key = newKey
                    status = .waiting
                    startPolling(key: newKey)
                }
            } catch {
                await MainActor.run {
                    status = .error(error.localizedDescription)
                }
            }
        }
    }

    private func startPolling(key: String) {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task {
                do {
                    let code = try await NetEaseAPI.shared.qrCheck(key: key)
                    await MainActor.run {
                        handle(code)
                    }
                } catch {
                    // 网络抖动：跳过本次轮询，等待下一次
                }
            }
        }
    }

    private func handle(_ code: Int) {
        switch code {
        case 800:
            timer?.invalidate()
            timer = nil
            status = .expired
        case 802:
            status = .scanned
        case 803:
            timer?.invalidate()
            timer = nil
            status = .success
            Task {
                do {
                    try await auth.finishLogin()
                    // 登录成功：二维码区域自动收起，无需手动下拉关闭
                    dismiss()
                } catch {
                    status = .error(error.localizedDescription)
                }
            }
        default:
            if status == .scanned {
                status = .waiting
            }
        }
    }
}
