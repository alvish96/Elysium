import Foundation
import Security

public final class KeychainHelper: @unchecked Sendable {
    public static let shared = KeychainHelper()

    private let service: String = "link.nexus.music"
    private let lock = NSLock()

    public enum Key: String, CaseIterable {
        case jwtToken = "jwt_token"
        case username = "username"
        case subsonicPass = "subsonic_pass"
    }

    private init() {}

    @discardableResult
    public func save(key: String, data: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let dataBytes = data.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        var newQuery = query
        newQuery[kSecValueData as String] = dataBytes
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(newQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func read(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func delete(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public func clearAll() {
        for key in Key.allCases {
            delete(key: key.rawValue)
        }
    }

    // MARK: - Strongly-Typed Helpers

    @discardableResult
    public func save(_ key: Key, value: String) -> Bool {
        save(key: key.rawValue, data: value)
    }

    public func read(_ key: Key) -> String? {
        read(key: key.rawValue)
    }

    @discardableResult
    public func delete(_ key: Key) -> Bool {
        delete(key: key.rawValue)
    }
}
