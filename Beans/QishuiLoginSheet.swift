import SwiftUI
import UIKit

/// 汽水音乐登录：后端生成二维码，用户使用抖音 App 扫码确认。
struct QishuiLoginSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var qr: QishuiQRCode?
    @State private var status: QRStatus = .loading
    @State private var timer: Timer?

    var body: some View {
        let _ = theme.accent
        ZStack {
            GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            VStack(spacing: 18) {
                Capsule()
                    .fill(Color.beansComment.opacity(0.3))
                    .frame(width: 38, height: 4)
                    .padding(.top, 12)

                HStack {
                    Text("登录汽水音乐")
                        .font(BeansFont.appFont(20, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Spacer()
                    Button {
                        BeansHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.beansComment)
                    }
                    .buttonStyle(GlassPressButtonStyle(scale: 0.9))
                }
                .padding(.horizontal, 24)

                qrArea
                    .frame(width: 250, height: 250)
                    .padding(18)
                    .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 30, style: .continuous)) }
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)

                statusView

                Text(qr?.copywriting ?? "请使用抖音 App 扫码确认登录")
                    .font(BeansFont.appFont(11))
                    .foregroundStyle(Color.beansComment)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer(minLength: 0)
            }
        }
        .onAppear { startLogin() }
        .onDisappear { timer?.invalidate() }
    }

    @ViewBuilder
    private var qrArea: some View {
        ZStack {
            if let qr {
                QishuiQRCodeImage(value: qr.image)
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
                Text("正在生成汽水音乐二维码…")
            case .waiting:
                Label("请使用抖音 App 扫码", systemImage: "qrcode.viewfinder")
            case .scanned:
                Label("已扫码，请在手机上确认登录", systemImage: "checkmark.circle")
            case .success:
                Label("登录成功，正在同步歌单…", systemImage: "checkmark.seal.fill")
            case .expired:
                Text("二维码已过期")
            case .error(let message):
                Text(message)
            }
        }
        .font(BeansFont.appFont(13))
        .foregroundStyle(isError ? Color.red.opacity(0.85) : Color.beansComment)
        .multilineTextAlignment(.center)
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

    private func startLogin() {
        timer?.invalidate()
        timer = nil
        qr = nil
        status = .loading
        Task {
            do {
                let newQR = try await QishuiAPI.shared.requestQRCode()
                await MainActor.run {
                    qr = newQR
                    status = .waiting
                    startPolling(token: newQR.token, expiresAt: newQR.expiresAt)
                }
            } catch {
                await MainActor.run { status = .error(error.localizedDescription) }
            }
        }
    }

    private func startPolling(token: String, expiresAt: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            if expiresAt > 0, Date().timeIntervalSince1970 >= expiresAt {
                timer?.invalidate()
                timer = nil
                status = .expired
                return
            }
            Task {
                do {
                    let finished = try await QishuiAPI.shared.pollQRCode(token: token)
                    if finished { await MainActor.run { loginSucceeded() } }
                } catch {
                    // 网络抖动时保留二维码，下一轮继续轮询。
                }
            }
        }
    }

    private func loginSucceeded() {
        timer?.invalidate()
        timer = nil
        status = .success
        NotificationCenter.default.post(name: .beansQishuiLoginDidUpdate, object: nil)
        ToastCenter.shared.show("汽水音乐登录成功")
        dismiss()
    }
}

private struct QishuiQRCodeImage: View {
    let value: String

    var body: some View {
        if let data = decodedData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(12)
        } else if let url = URL(string: value), url.scheme != nil {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().padding(12)
                } else if phase.error != nil {
                    QRCodeView(text: value)
                } else {
                    ProgressView().tint(Color.beansAmber)
                }
            }
        } else {
            QRCodeView(text: value)
                .padding(12)
        }
    }

    private var decodedData: Data? {
        guard let comma = value.firstIndex(of: ",") else {
            return Data(base64Encoded: value)
        }
        return Data(base64Encoded: String(value[value.index(after: comma)...]))
    }
}
