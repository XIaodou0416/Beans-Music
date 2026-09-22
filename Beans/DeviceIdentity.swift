import Foundation
import Security
import UIKit
import Darwin
import CryptoKit

enum DeviceIdentity {
    private static let service = "com.beans.music.device"
    private static let account = "anonymous-user-id"
    private static let publicIDAccount = "public-user-id"
    private static let originalPublicIDAccount = "original-public-user-id"
    private static let developerIdentifierHash = "f6073926d77dd0947338f5f27f133201a484a2d2b28f68f7fbd95cb168526d36"

    static let userID: String = {
        if let value = loadFromKeychain(), !value.isEmpty {
            return value
        }
        let generated = UUID().uuidString.lowercased()
        saveToKeychain(generated)
        return generated
    }()

    /// A user-facing identifier that survives app updates and reinstalls
    /// through the device keychain. The developer device starts with its
    /// familiar ID, but it can be changed through developer tools as well.
    static var publicID: String {
        if let value = loadFromKeychain(account: publicIDAccount),
           isValidPublicID(value) {
            if loadFromKeychain(account: originalPublicIDAccount) == nil {
                saveToKeychain(value, account: originalPublicIDAccount)
            }
            return value
        }
        if let value = UserDefaults.standard.string(forKey: "beans.stablePublicID"),
           isValidPublicID(value) {
            saveToKeychain(value, account: publicIDAccount)
            if loadFromKeychain(account: originalPublicIDAccount) == nil {
                saveToKeychain(value, account: originalPublicIDAccount)
            }
            return value
        }
        let generated = isDeveloperInstallation ? "5201314" : String(Int.random(in: 100000...500000))
        saveToKeychain(generated, account: publicIDAccount)
        saveToKeychain(generated, account: originalPublicIDAccount)
        UserDefaults.standard.set(generated, forKey: "beans.stablePublicID")
        return generated
    }

    /// The first public ID assigned to this installation, retained when the
    /// developer later renames the visible ID.
    static var originalPublicID: String {
        if let value = loadFromKeychain(account: originalPublicIDAccount),
           isValidPublicID(value) {
            return value
        }
        let value = publicID
        saveToKeychain(value, account: originalPublicIDAccount)
        return value
    }

    /// The backend may assign a new public ID from the developer tools. Public
    /// IDs are labels and are intentionally allowed to repeat.
    static func updatePublicID(_ value: String) {
        guard isValidPublicID(value) else {
            return
        }
        saveToKeychain(value, account: publicIDAccount)
        UserDefaults.standard.set(value, forKey: "beans.stablePublicID")
    }

    static func isValidPublicID(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard !scalars.isEmpty, scalars.count <= 24 else { return false }
        return scalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.controlCharacters.contains($0)
        }
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
