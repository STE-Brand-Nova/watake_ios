import CryptoKit
import Foundation
import Testing
@testable import WatakeStorage

@Suite("Encryption key store")
struct EncryptionKeyStoringTests {
    @Test("recovers when SecItemAdd reports a duplicate item from a concurrent writer")
    func recoversFromDuplicateItemRace() throws {
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let store = KeychainEncryptionKeyStore(service: service)

        let winner = SymmetricKey(size: .bits256)
        try store.store(winner)

        let loser = SymmetricKey(size: .bits256)
        let resolved = try store.createAndStoreIfAbsent(loser)

        #expect(resolved.withUnsafeBytes { Data($0) } == winner.withUnsafeBytes { Data($0) })
    }

    @Test("loadOrCreateEncryptionKey returns a stable key across repeated calls")
    func loadOrCreateIsStable() throws {
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let store = KeychainEncryptionKeyStore(service: service)

        let first = try store.loadOrCreateEncryptionKey()
        let second = try store.loadOrCreateEncryptionKey()

        #expect(first.withUnsafeBytes { Data($0) } == second.withUnsafeBytes { Data($0) })
    }
}
