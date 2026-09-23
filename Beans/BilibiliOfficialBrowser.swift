import SwiftUI
import WebKit
import SafariServices

/// The official site owns sign-in and every account action. This view neither
/// injects scripts nor transfers the app's keychain credentials to web content.
struct BilibiliOfficialBrowser: View {
    let page: BilibiliOfficialPage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        BeansNavigationStack {
            BilibiliOfficialContent(url: page.url)
                .navigationTitle(page.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                }
        }
    }
}

struct BilibiliOfficialContent: View {
    let url: URL
    @StateObject private var browser = BilibiliWebState()
    @State private var externalPage: BilibiliOfficialPage?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button { browser.back() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(!browser.canGoBack).accessibilityLabel("网页后退")
                Text("哔哩哔哩官方网页").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button { externalPage = BilibiliOfficialPage(url: browser.currentURL ?? url, title: "在浏览器打开") } label: {
                    Image(systemName: "safari").frame(width: 44, height: 44)
                }.accessibilityLabel("用系统浏览器打开")
            }.padding(.horizontal, 8)
            if browser.loading { ProgressView().frame(maxWidth: .infinity).frame(height: 2) }
            if let error = browser.error {
                VStack(spacing: 8) {
                    Text(error).font(.caption).multilineTextAlignment(.center)
                    Button("重试") { browser.reload() }.frame(minHeight: 44)
                }.padding()
            }
            BilibiliWebView(url: url, state: browser)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $externalPage) { item in BilibiliSafariPage(url: item.url) }
        .onDisappear { browser.stopMedia() }
    }
}

struct BilibiliSafariPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

@MainActor
final class BilibiliWebState: ObservableObject {
    @Published var loading = false
    @Published var canGoBack = false
    @Published var error: String?
    @Published var currentURL: URL?
    weak var webView: WKWebView?
    func back() { webView?.goBack() }
    func reload() { error = nil; webView?.reload() }
    func stopMedia() { webView?.pauseAllMediaPlayback(completionHandler: nil) }
}

private struct BilibiliWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: BilibiliWebState
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        view.scrollView.alwaysBounceVertical = true
        view.scrollView.refreshControl = refresh
        state.webView = view
        context.coordinator.load(url, in: view)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.requestedURL != url { context.coordinator.load(url, in: view) }
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: BilibiliWebState
        var requestedURL: URL?
        init(state: BilibiliWebState) { self.state = state }
        func load(_ url: URL, in view: WKWebView) {
            requestedURL = url
            view.load(URLRequest(url: url))
        }
        @objc func refresh(_ sender: UIRefreshControl) { state.reload() }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.loading = true; state.error = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.loading = false; state.canGoBack = webView.canGoBack; state.currentURL = webView.url
            webView.scrollView.refreshControl?.endRefreshing()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(webView, error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(webView, error) }
        private func failed(_ view: WKWebView, _ error: Error) {
            state.loading = false
            view.scrollView.refreshControl?.endRefreshing()
            if (error as NSError).code != NSURLErrorCancelled { state.error = error.localizedDescription }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if ["https", "http", "about", "blob"].contains(url.scheme?.lowercased() ?? "") {
                decisionHandler(.allow)
            } else {
                // App-deep-link redirects are not launched automatically.
                decisionHandler(.cancel)
                if navigationAction.navigationType == .linkActivated {
                    state.error = "该功能需要官方App；可使用上方浏览器入口继续。"
                }
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
               ["http", "https"].contains(url.scheme ?? "") { webView.load(navigationAction.request) }
            return nil
        }
    }
}
