import SwiftUI
import WebKit

// MARK: - QQ 音乐网页登录（应用内网页登录 y.qq.com，登录后直接读取 Cookie）
// 原理：WKWebView 打开 QQ 音乐网页版，用户完成 QQ 登录后，登录态 Cookie
// （uin / p_skey / qqmusic_key / qm_keyst 等）写入 WKWebView 的默认 Cookie 存储，
// 应用直接读取这些 Cookie 完成登录，无需逆向授权接口。

struct QQWebLoginPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var pageLoaded = false
    @State private var syncing = false
    @State private var message = ""
    let onSuccess: () -> Void

    var body: some View {
        let _ = theme.accent
        VStack(spacing: 10) {
            Text("在下方网页右上角点「登录」，完成后手动点击下方「同步登录状态」")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            ZStack {
                QQWebView(onLoaded: { pageLoaded = true })
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .padding(.horizontal, 20)

                if !pageLoaded {
                    ProgressView("正在加载 QQ 音乐…")
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
            let auth = QQMusicAuth.shared
            if let issue = QQMusicAuth.loginValidationMessage(dict) {
                message = issue
            } else {
                auth.importCookies(dict, nickname: nil)
                finishSuccess()
            }
        }
    }

    private func finishSuccess() {
        message = "✓ QQ 音乐登录成功"
        BeansHaptics.success()
        ToastCenter.shared.show("QQ 音乐登录成功")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onSuccess()
        }
    }

    /// 从 WKWebView 默认 Cookie 存储读取登录态 Cookie
    private func readCookies(_ completion: @escaping ([String: String]) -> Void) {
        let wanted = QQMusicAuth.webCookieNames
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            var dict: [String: String] = [:]
            for cookie in cookies where wanted.contains(cookie.name) || cookie.name.hasPrefix("ptnick") {
                dict[cookie.name] = cookie.value
            }
            // 兜底：微信登录可能使用动态 Cookie 名，收下 QQ 域全部 Cookie。
            if QQMusicAuth.loginValidationMessage(dict) != nil {
                for cookie in cookies where cookie.domain.lowercased().hasSuffix("qq.com") {
                    dict[cookie.name] = cookie.value
                }
            }
            DispatchQueue.main.async {
                completion(dict)
            }
        }
    }
}

// MARK: - 手动粘贴 Cookie（浏览器 F12 复制，最稳的兜底方式）

struct QQCookieImportPanel: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var cookieText = ""
    @State private var message = ""
    let onSuccess: () -> Void

    var body: some View {
        let _ = theme.accent
        VStack(spacing: 12) {
            Text("电脑浏览器打开 https://y.qq.com 登录 QQ 后，按 F12 → Network → 刷新页面，点任意请求，复制 Request Headers 里的整段 Cookie 粘贴到下方")
                .font(BeansFont.appFont(12))
                .foregroundStyle(Color.beansComment)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            TextEditor(text: $cookieText)
                .font(BeansFont.appFont(11, .regular, .monospaced))
                .beansScrollContentBackgroundHidden()
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(height: 160)
                .padding(.horizontal, 20)

            if !message.isEmpty {
                Text(message)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(message.hasPrefix("✓") ? Color.beansSage : Color.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button {
                importCookie()
            } label: {
                Label("导入 Cookie", systemImage: "arrow.down.doc")
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.beansAmber, in: Capsule())
            }
            .buttonStyle(GlassPressButtonStyle(scale: 0.96))
            .padding(.horizontal, 20)

            Spacer(minLength: 8)
        }
        .padding(.top, 8)
    }

    private func importCookie() {
        let dict = QQMusicAuth.parseCookieHeader(cookieText)
        let auth = QQMusicAuth.shared
        guard auth.hasValidLogin(dict) else {
            message = "Cookie 格式或登录态无效，请确认已完整复制"
            return
        }
        auth.importCookies(dict, nickname: nil)
        message = "✓ QQ 音乐登录成功"
        BeansHaptics.success()
        ToastCenter.shared.show("QQ 音乐登录成功")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onSuccess()
        }
    }
}

// MARK: - WKWebView 封装（打开 QQ 音乐网页版）

struct QQWebView: UIViewRepresentable {
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
        if let url = URL(string: "https://y.qq.com/") {
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
