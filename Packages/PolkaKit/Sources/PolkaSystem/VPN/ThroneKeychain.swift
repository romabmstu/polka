import Foundation
import Security

/// The Throne API key is a local control credential, never stored in preferences.
public enum ThroneKeychain {
    public enum Failure: Error { case keychain(OSStatus) }
    private static let service = "io.github.romabmstu.Polka.ThroneAPI"
    private static let account = "local"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public static func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let result = SecItemCopyMatching(request as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess else { throw Failure.keychain(result) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw Failure.keychain(errSecDecode)
        }
        return key
    }
    public static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure.keychain(update) }
        var request = query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(request as CFDictionary, nil)
        guard result == errSecSuccess else { throw Failure.keychain(result) }
    }
    public static func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw Failure.keychain(result) }
    }
}
