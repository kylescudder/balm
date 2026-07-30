import Foundation
import Security

/// Single-entry generic password store keyed by (service, account).
/// Stores a Codable payload as JSON in the Keychain.
public struct KeychainStore: Sendable {
    public let service: String
    public let account: String
    public let accessGroup: String?

    public init(service: String, account: String, accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private func baseQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let group = accessGroup {
            q[kSecAttrAccessGroup as String] = group
        }
        return q
    }

    public func save<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        var query = baseQuery()

        // Try to update first.
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw AuthError.keychainFailure(updateStatus)
        }

        // No existing entry — add.
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AuthError.keychainFailure(addStatus)
        }
    }

    public func load<T: Decodable>(_ type: T.Type) throws -> T? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AuthError.keychainFailure(status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw AuthError.keychainFailure(status)
        }
    }
}

public extension KeychainStore {
    static let balmService = "app.balm.atlassian"
    static let balmAccount = "primary"

    static let live = KeychainStore(service: balmService, account: balmAccount)
}
