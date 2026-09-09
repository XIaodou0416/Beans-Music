import SwiftUI
import WebKit

// MARK: - 网易云网页登录（应用内网页登录 music.163.com，登录后直接读取 Cookie）
// 原理：WKWebView 打开网易云网页版登录页，用户完成扫码 / 手机号登录后，
// 登录态 Cookie（MUSIC_U、__csrf 等）写入 WKWebView 默认 Cookie 存储，
// 应用读取这些 Cookie 合并进 NetEaseAPI 登录态并同步账号歌单，无需逆向接口。

struct NetEaseWebLoginPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void

    @State private var pageLoaded = false
    @State private var syncing = false
    @State private var message = ""

    var body: some View {
        let _ = theme.accent
        VStack(spacing: 10) {
            Text("在下方网页中完成网易云登录，完成后手动点击下方「同步登录状态」")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            ZStack {
                NetEaseWebView(onLoaded: { pageLoaded = true })
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .padding(.horizontal, 20)

                if !pageLoaded {
                    ProgressView("正在加载网易云音乐…")
                        .tint(Color.beansAmber)
                }
            }
            .frame(maxHeight: .infinity)

            if !message.isEmpty {
                Text(message)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(message.hasPrefix("✓") ? Color.beansSage : Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button {
                syncNow()
            } label: {
                HStack(spacing: 6) {
                    if syncing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(syncing ? "正在读取登录状态…" : "同步登录状态")
                }
                .font(BeansFont.appFont(14, .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.beansAmber, in: Capsule())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.96))
            .disabled(syncing)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: - 手动同步

    private func syncNow() {
        syncing = true
        message = ""
        readCookies { dict in
            syncing = false
            guard !(dict["MUSIC_U"] ?? "").isEmpty else {
                message = "未检测到有效登录态，请先在网页中完成网易云登录"
                return
            }
            NetEaseAPI.shared.importWebCookies(dict)
            finishSuccess()
        }
    }

    private func finishSuccess() {
        message = "✓ 网易云登录成功，正在同步…"
        BeansHaptics.success()
        ToastCenter.shared.show("网易云登录成功")
        Task {
            do {
                try await auth.finishLogin()
                await MainActor.run {
                    dismiss()
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    message = "同步账号失败：\(error.localizedDescription)"
                }
            }
        }
    }

    /// 从 WKWebView 默认 Cookie 存储读取网易云登录态 Cookie
    private func readCookies(_ completion: @escaping ([String: String]) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            var dict: [String: String] = [:]
            for cookie in cookies where cookie.domain.contains("music.163.com") || cookie.domain.contains(".163.com") {
                dict[cookie.name] = cookie.value
            }
            DispatchQueue.main.async {
                completion(dict)
            }
        }
    }
}

// MARK: - WKWebView 封装（打开网易云网页版登录页）

struct NetEaseWebView: UIViewRepresentable {
    let onLoaded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: "https://music.163.com/#/login") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoaded: () -> Void

        init(onLoaded: @escaping () -> Void) {
            self.onLoaded = onLoaded
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.onLoaded()
            }
        }
    }
}
