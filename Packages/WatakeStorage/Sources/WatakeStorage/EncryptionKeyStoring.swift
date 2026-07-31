import CryptoKit
import Foundation
import Security

public protocol EncryptionKeyStoring: Sendable {
    func loadOrCreateEncryptionKey() throws -> SymmetricKey
}

public struct KeychainEncryptionKeyStore: EncryptionKeyStoring {
    private let service: String
    private let account: String

    public init(service: String, account: String = "encryption-key") {
        self.service = service
        self.account = account
    }

    public func loadOrCreateEncryptionKey() throws -> SymmetricKey {
        if let existing = try readKey() {
            return existing
        }
        return try createAndStoreIfAbsent(SymmetricKey(size: .bits256))
    }

    /// Internal seam so tests can force the duplicate-item recovery path deterministically.
    func createAndStoreIfAbsent(_ key: SymmetricKey) throws -> SymmetricKey {
        do {
            try store(key)
            return key
        } catch KeychainRaceError.duplicateItem {
            guard let existing = try readKey() else {
                throw StorageError.keychainUnavailable
            }
            return existing
        }
    }

    func readKey() throws -> SymmetricKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw StorageError.keychainUnavailable
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw StorageError.keychainUnavailable
        }
    }

    func store(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        var attributes = baseQuery()
        attributes[kSecValueData as String] = keyData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeychainRaceError.duplicateItem
        default:
            throw StorageError.keychainUnavailable
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainRaceError: Error {
    case duplicateItem
}
