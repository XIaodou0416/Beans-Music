import Foundation
import Security
import UIKit
import Darwin

enum DeviceIdentity {
    private static let service = "com.beans.music.device"
    private static let account = "anonymous-user-id"

    static let userID: String = {
        if let value = loadFromKeychain(), !value.isEmpty {
            return value
        }
        let generated = UUID().uuidString.lowercased()
        saveToKeychain(generated)
        return generated
    }()

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
        default: return "application/octet-stream"
        }
    }

    private static func loadFromKeychain() -> String? {
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

    private static func saveToKeychain(_ value: String) {
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
