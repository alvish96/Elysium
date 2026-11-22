import Foundation
import Security

public final class KeychainHelper: @unchecked Sendable {
    public static let shared = KeychainHelper()
    private let service = "link.nexus.galactic"
    private let lock = NSLock()

    public enum Key: String, CaseIterable {
        case jwtToken = "jwt_token"
        case username = "username"
        case subsonicPass = "subsonic_pass"
    }

    private init() {}

    @discardableResult
    public func save(_ key: Key, value: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    public func read(_ key: Key) -> String? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func delete(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public func clearAll() {
        Key.allCases.forEach { _ = delete($0) }
    }
}
