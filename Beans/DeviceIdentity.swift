import Foundation
import Security
import UIKit
import Darwin
import CryptoKit

enum DeviceIdentity {
    private static let service = "com.beans.music.device"
    private static let account = "anonymous-user-id"
    private static let publicIDAccount = "public-user-id"
    private static let developerIdentifierHash = "f6073926d77dd0947338f5f27f133201a484a2d2b28f68f7fbd95cb168526d36"

    static let userID: String = {
        if let value = loadFromKeychain(), !value.isEmpty {
            return value
        }
        let generated = UUID().uuidString.lowercased()
        saveToKeychain(generated)
        return generated
    }()

    /// A short, user-facing identifier that survives app updates and reinstalls
    /// through the device keychain. The developer installation keeps its
    /// reserved identifier so it can be recognized by the backend.
    static var publicID: String {
        if isDeveloperInstallation {
            return "5201314"
        }
        if let value = loadFromKeychain(account: publicIDAccount),
           value.range(of: #"^[0-9]{6,7}$"#, options: .regularExpression) != nil {
            return value
        }
        let generated = String(Int.random(in: 100000...500000))
        saveToKeychain(generated, account: publicIDAccount)
        return generated
    }

    /// The backend may assign a new, unique public ID from the developer
    /// tools. Keep the value in the keychain so it survives app updates.
    static func updatePublicID(_ value: String) {
        guard !isDeveloperInstallation,
              value.range(of: #"^[0-9]{6,7}$"#, options: .regularExpression) != nil else {
            return
        }
        saveToKeychain(value, account: publicIDAccount)
    }

    static var isDeveloperInstallation: Bool {
        let data = Data(userID.lowercased().utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == developerIdentifierHash
    }

    static var hardwareModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    static func mimeType(for url: URL) -> String {
        let extensionType = url.pathExtension.lowercased()
        switch extensionType {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "js", "mjs", "cjs": return "application/javascript"
        case "ts", "tsx": return "text/typescript"
        case "json": return "application/json"
        case "txt", "log", "md", "swift": return "text/plain"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }

    private static func loadFromKeychain(account: String = account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func saveToKeychain(_ value: String, account: String = account) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
