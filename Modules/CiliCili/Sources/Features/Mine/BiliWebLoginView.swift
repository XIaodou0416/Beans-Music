import SwiftUI
import WebKit

struct BiliWebLoginView: View {
    @Environment(\.dismiss) private var dismiss
    var usesIsolatedSession = false
    let onLoginCookies: ([HTTPCookie]) -> Void

    var body: some View {
        NavigationStack {
            BiliWebLoginWebView(usesIsolatedSession: usesIsolatedSession) { cookies in
                onLoginCookies(cookies)
                dismiss()
            }
            .hiddenInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BiliWebLoginWebView: UIViewRepresentable {
    private static let loginURL = URL(string: "https://passport.bilibili.com/login")!

    let usesIsolatedSession: Bool
    let onLoginCookies: ([HTTPCookie]) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = usesIsolatedSession ? .nonPersistent() : .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        var request = URLRequest(url: Self.loginURL)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoginCookies: onLoginCookies)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let onLoginCookies: ([HTTPCookie]) -> Void
        private var didCompleteLogin = false

        init(onLoginCookies: @escaping ([HTTPCookie]) -> Void) {
            self.onLoginCookies = onLoginCookies
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            inspectCookies(in: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            inspectCookies(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
                decisionHandler(.cancel)
                return
            }
            inspectCookies(in: webView)
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func inspectCookies(in webView: WKWebView) {
            guard !didCompleteLogin else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.didCompleteLogin else { return }

                let biliCookies = cookies.filter { cookie in
                    BiliWebCookieStore.isStorableBiliCookie(cookie)
                }

                guard biliCookies.contains(where: { $0.name == "SESSDATA" }) else { return }
                self.didCompleteLogin = true

                DispatchQueue.main.async {
                    self.onLoginCookies(biliCookies)
                }
            }
        }
    }
}

enum BiliWebCookieStore {
    private static let storableCookieNames = Set([
        "buvid3",
        "buvid4",
        "b_nut",
        "buvid_fp",
        "buvid_fp_plain",
        "_uuid",
        "b_lsid",
        "bili_ticket",
        "bili_ticket_expires",
        "DedeUserID",
        "DedeUserID__ckMd5",
        "SESSDATA",
        "access_key",
        "bili_jct",
        "sid",
        "CURRENT_FNVAL",
        "CURRENT_QUALITY"
    ])

    static func isStorableBiliCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.domain.localizedCaseInsensitiveContains("bilibili.com")
            && storableCookieNames.contains(cookie.name)
            && !cookie.value.isEmpty
    }

    static func clearLoginCookies() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where isStorableBiliCookie(cookie) {
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
            }
        }
    }
}
