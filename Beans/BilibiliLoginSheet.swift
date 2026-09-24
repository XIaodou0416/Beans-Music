import SwiftUI
import Security
import CoreImage
import CoreImage.CIFilterBuiltins

extension Notification.Name {
    static let beansBilibiliLoginDidUpdate = Notification.Name("beansBilibiliLoginDidUpdate")
}

@MainActor
final class BilibiliAuth: ObservableObject {
    static let shared = BilibiliAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var nickname = ""
    @Published private(set) var accountID = ""
    @Published private(set) var avatarURL: URL?

    private static let service = "com.beans.music.bilibili"
    private static let cookieAccount = "account-cookie-v1"
    private let defaults = UserDefaults.standard

    private init() {
        nickname = defaults.string(forKey: "beans.bilibili.nickname.v1") ?? ""
        accountID = defaults.string(forKey: "beans.bilibili.mid.v1") ?? ""
        avatarURL = defaults.string(forKey: "beans.bilibili.avatar.v1").flatMap { URL(string: $0) }
        if let cookie = Self.readCookie(), !cookie.isEmpty {
            isLoggedIn = true
        }
    }

    var cookieHeader: String { BilibiliProtocol.normalizeCookie(Self.readCookie() ?? "") }

    func login(cookie: String) async throws {
        let normalized = BilibiliProtocol.normalizeCookie(cookie)
        guard BilibiliProtocol.hasSession(normalized) else {
            throw BilibiliError(message: "登录凭据不完整，请重新扫码")
        }
        let info = try await BilibiliAPI.shared.accountInfo(cookie: normalized)
        try Self.saveCookie(normalized)
        await BilibiliAPI.shared.setCookie(normalized)
        nickname = info.nickname
        accountID = info.mid
        isLoggedIn = true
        avatarURL = info.avatar
        defaults.set(info.nickname, forKey: "beans.bilibili.nickname.v1")
        defaults.set(info.mid, forKey: "beans.bilibili.mid.v1")
        defaults.set(info.avatar?.absoluteString, forKey: "beans.bilibili.avatar.v1")
        NotificationCenter.default.post(name: .beansBilibiliLoginDidUpdate, object: nil)
    }

    func logout() {
        Self.deleteCookie()
        nickname = ""
        accountID = ""
        avatarURL = nil
        isLoggedIn = false
        defaults.removeObject(forKey: "beans.bilibili.nickname.v1")
        defaults.removeObject(forKey: "beans.bilibili.mid.v1")
        defaults.removeObject(forKey: "beans.bilibili.avatar.v1")
        Task { await BilibiliAPI.shared.setCookie("") }
        NotificationCenter.default.post(name: .beansBilibiliLoginDidUpdate, object: nil)
    }

    private static func readCookie() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cookieAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveCookie(_ cookie: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cookieAccount
        ]
        let data = Data(cookie.utf8)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let update = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        guard update == errSecItemNotFound else {
            guard update == errSecSuccess else {
                throw BilibiliError(message: "无法安全保存哔哩哔哩登录凭据（\(update)）")
            }
            return
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else {
            throw BilibiliError(message: "无法安全保存哔哩哔哩登录凭据（\(add)）")
        }
    }

    private static func deleteCookie() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cookieAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
struct BilibiliLoginSheet: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = BilibiliAuth.shared
    @State private var qrURL = ""
    @State private var qrKey = ""
    @State private var status = "正在生成二维码"
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var loading = true

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                VStack(spacing: 18) {
                    Text("哔哩哔哩扫码登录")
                        .font(BeansFont.appFont(22, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Group {
                        if let image = qrImage {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 228, height: 228)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(errorMessage ?? status)
                        .font(BeansFont.appFont(14, .medium))
                        .foregroundStyle(errorMessage == nil ? Color.beansComment : Color.red)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await loadQRCode() }
                    } label: {
                        Label("刷新二维码", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(loading)
                    Text("登录信息仅保存在本机钥匙串，用于读取你的收藏夹。")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .navigationTitle("账号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await loadQRCode() }
        .onDisappear { pollTask?.cancel() }
        .modifier(BeansSheetModifier(detents: [.medium, .large], dragIndicator: true))
    }

    private var qrImage: UIImage? {
        guard let data = qrURL.data(using: .utf8), !qrURL.isEmpty,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func loadQRCode() async {
        pollTask?.cancel()
        loading = true
        errorMessage = nil
        do {
            let result = try await BilibiliAPI.shared.loginQR()
            qrURL = result.url
            qrKey = result.key
            status = "请使用哔哩哔哩 App 扫码并确认"
            loading = false
            beginPolling(key: result.key)
        } catch {
            loading = false
            errorMessage = error.localizedDescription
        }
    }

    private func beginPolling(key: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    let result = try await BilibiliAPI.shared.pollQR(key)
                    try Task.checkCancellation()
                    guard qrKey == key else { return }
                    errorMessage = nil
                    switch result.code {
                    case 0:
                        if result.cookie.isEmpty {
                            errorMessage = "扫码已确认，但未取得登录凭据，请刷新二维码重试。"
                            return
                        }
                        status = "正在验证登录状态"
                        // A successful QR token is one-use. Retry verification with
                        // its captured cookie instead of polling the token again.
                        for attempt in 0..<3 {
                            do {
                                try Task.checkCancellation()
                                try await auth.login(cookie: result.cookie)
                                dismiss()
                                return
                            } catch is CancellationError {
                                return
                            } catch {
                                if attempt == 2 {
                                    errorMessage = error.localizedDescription
                                    return
                                }
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                            }
                        }
                        return
                    case 86101:
                        status = "请使用哔哩哔哩 App 扫码"
                    case 86090:
                        status = "已扫码，请在手机上确认登录"
                    case 86038, 86083:
                        status = "二维码已过期，请刷新"
                        return
                    default:
                        status = "等待扫码确认"
                    }
                } catch is CancellationError {
                    return
                } catch {
                    errorMessage = error.localizedDescription
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }
}
