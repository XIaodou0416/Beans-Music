import SwiftUI
import WebKit

/// CiliCili uses a system glass surface for every floating control. BeansGlass
/// keeps the same interaction model while remaining compatible with iOS 15.
struct BilibiliVideoTabBarHider: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { hideTabBar(from: view) }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { hideTabBar(from: view) }
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        DispatchQueue.main.async { restoreTabBar(from: view) }
    }

    private func hideTabBar(from view: UIView) {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UITabBarController {
                controller.tabBar.isHidden = true
                return
            }
            responder = current.next
        }
    }

    private static func restoreTabBar(from view: UIView) {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UITabBarController {
                controller.tabBar.isHidden = false
                return
            }
            responder = current.next
        }
    }
}

struct BilibiliPlaybackSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var quality: Int
    @AppStorage("beans.bilibili.danmakuEnabled") private var danmakuEnabled = true
    @AppStorage("beans.bilibili.pipEnabled") private var pipEnabled = true
    @AppStorage("beans.bilibili.controlScrimEnabled") private var controlScrimEnabled = true
    @AppStorage("beans.bilibili.listenVideoEnabled") private var listenVideoEnabled = false
    @AppStorage("beans.bilibili.playbackRate") private var playbackRate = 1.0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $quality) {
                        Text("流畅").tag(16)
                        Text("高清").tag(64)
                        Text("超清").tag(80)
                    } label: {
                        Label("清晰度", systemImage: "slider.horizontal.3")
                    }

                    Picker(selection: $playbackRate) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                            Text(value == 1 ? "1.0x" : "\(value, specifier: "%.2g")x").tag(value)
                        }
                    } label: {
                        Label("倍速", systemImage: "speedometer")
                    }

                    Toggle(isOn: $danmakuEnabled) {
                        Label("弹幕设置", systemImage: "captions.bubble")
                    }
                }

                Section {
                    Toggle(isOn: $listenVideoEnabled) {
                        Label("听视频", systemImage: "headphones")
                    }
                    Toggle(isOn: $pipEnabled) {
                        Label("画中画播放", systemImage: "pip")
                    }
                    Toggle(isOn: $controlScrimEnabled) {
                        Label("播放控件边缘遮罩", systemImage: "rectangle.topthird.inset.filled")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { BeansLiquidSheetBackground() }
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
    }
}

struct BilibiliSMSLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = BilibiliAuth.shared
    @State private var phone = ""
    @State private var code = ""
    @State private var captchaKey = ""
    @State private var message = ""
    @State private var sending = false
    @State private var loggingIn = false
    @State private var cooldown = 0
    @State private var cooldownTask: Task<Void, Never>?

    private var normalizedPhone: String { phone.filter(\.isNumber) }
    private var normalizedCode: String { code.filter(\.isNumber) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("手机号", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    HStack {
                        TextField("验证码", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button(cooldown > 0 ? "\(cooldown)s" : "获取验证码") {
                            sendCode()
                        }
                        .disabled(sending || loggingIn || cooldown > 0 || normalizedPhone.isEmpty)
                    }
                }

                if !message.isEmpty {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }

                Section {
                    Button {
                        login()
                    } label: {
                        HStack {
                            Spacer()
                            if loggingIn { ProgressView() } else { Text("手机号登录") }
                            Spacer()
                        }
                    }
                    .disabled(loggingIn || sending || captchaKey.isEmpty || normalizedCode.isEmpty)
                }
            }
            .navigationTitle("手机号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .onDisappear { cooldownTask?.cancel() }
    }

    private func sendCode() {
        sending = true
        message = ""
        Task { @MainActor in
            defer { sending = false }
            do {
                captchaKey = try await BilibiliAPI.shared.sendSMSCode(phone: normalizedPhone)
                message = "验证码已发送"
                cooldownTask?.cancel()
                cooldown = 60
                cooldownTask = Task { @MainActor in
                    while cooldown > 0, !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        if !Task.isCancelled { cooldown -= 1 }
                    }
                }
            } catch { message = error.localizedDescription }
        }
    }

    private func login() {
        loggingIn = true
        message = ""
        Task { @MainActor in
            defer { loggingIn = false }
            do {
                let cookie = try await BilibiliAPI.shared.loginSMS(phone: normalizedPhone, code: normalizedCode, captchaKey: captchaKey)
                try await auth.login(cookie: cookie)
                dismiss()
            } catch { message = error.localizedDescription }
        }
    }
}

struct BilibiliWebLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = BilibiliAuth.shared
    @State private var error: String?

    var body: some View {
        NavigationStack {
            BilibiliWebLoginWebView { cookie in
                Task { @MainActor in
                    do {
                        try await auth.login(cookie: cookie)
                        dismiss()
                    } catch { error = error.localizedDescription }
                }
            }
            .navigationTitle("网页登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .alert("登录失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

private struct BilibiliWebLoginWebView: UIViewRepresentable {
    let onCookie: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCookie: onCookie) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: URL(string: "https://passport.bilibili.com/login")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookie: (String) -> Void
        var completed = false

        init(onCookie: @escaping (String) -> Void) { self.onCookie = onCookie }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.completed else { return }
                let values = cookies.reduce(into: [String: String]()) { result, cookie in
                    guard cookie.domain.localizedCaseInsensitiveContains("bilibili.com") else { return }
                    if BilibiliProtocol.cookieNames.contains(cookie.name) { result[cookie.name] = cookie.value }
                }
                let header = BilibiliProtocol.cookieHeader(values)
                guard BilibiliProtocol.hasSession(header) else { return }
                self.completed = true
                DispatchQueue.main.async { self.onCookie(header) }
            }
        }
    }
}

struct BilibiliAccountHistoryPage: View {
    @Environment(\.bilibiliNavigate) private var navigate
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading && songs.isEmpty {
                ProgressView("加载观看记录")
            } else if let error {
                historyEmptyView(title: "观看记录加载失败", message: error)
            } else if songs.isEmpty {
                historyEmptyView(title: "暂无观看记录", message: nil)
            } else {
                List(songs) { song in
                    Button { navigate?(.video(song)) } label: {
                        HStack(spacing: 12) {
                            CoverImage(url: song.coverURL, size: 96, aspectRatio: 16.0 / 9.0, cornerRadius: 8)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(song.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                Text(song.artists).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("观看记录")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func historyEmptyView(title: String, message: String?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(24)
    }

    private func load() async {
        loading = true
        error = nil
        do { songs = try await BilibiliAPI.shared.accountHistoryVideos() }
        catch { error = error.localizedDescription }
        loading = false
    }
}

struct BilibiliPlaybackPreferencesPage: View {
    @AppStorage("beans.bilibili.danmakuEnabled") private var danmakuEnabled = true
    @AppStorage("beans.bilibili.pipEnabled") private var pipEnabled = true
    @AppStorage("beans.bilibili.controlScrimEnabled") private var controlScrimEnabled = true
    @AppStorage("beans.bilibili.listenVideoEnabled") private var listenVideoEnabled = false
    @AppStorage("beans.bilibili.playbackRate") private var playbackRate = 1.0
    @AppStorage("beans.bilibili.defaultQuality") private var quality = 64

    var body: some View {
        List {
            Section("播放设置") {
                Picker("清晰度", selection: $quality) {
                    Text("流畅").tag(16)
                    Text("高清").tag(64)
                    Text("超清").tag(80)
                }
                Picker("倍速", selection: $playbackRate) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                        Text("\(value, specifier: "%.2g")x").tag(value)
                    }
                }
                Toggle("弹幕", isOn: $danmakuEnabled)
                Toggle("听视频", isOn: $listenVideoEnabled)
                Toggle("画中画播放", isOn: $pipEnabled)
                Toggle("播放控件边缘遮罩", isOn: $controlScrimEnabled)
            }
        }
        .navigationTitle("播放设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

