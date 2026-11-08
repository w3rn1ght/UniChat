import Foundation
import Security

/// Хранилище API-ключей.
///
/// Основной путь — Keychain. На неподписанных сборках (джейлбрейк, AppSync)
/// Keychain может вернуть -34018 (нет entitlements). В этом случае ключ
/// сохраняется в UserDefaults, чтобы приложение оставалось рабочим.
enum Keychain {

    private static let service = "com.unichat.apikey"
    private static let fallbackPrefix = "unichat.keychainFallback."

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let base = baseQuery(account: account)
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        if SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey(account))
            return true
        }

        UserDefaults.standard.set(value, forKey: fallbackKey(account))
        return false
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        return UserDefaults.standard.string(forKey: fallbackKey(account))
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey(account))
    }

    private static func baseQuery(account: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func fallbackKey(_ account: String) -> String {
        return fallbackPrefix + account
    }
}
