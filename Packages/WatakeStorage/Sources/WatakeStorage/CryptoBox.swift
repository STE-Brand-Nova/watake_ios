import CryptoKit
import Foundation

enum CryptoBox {
    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealedBox.combined else {
                throw StorageError.cryptoFailure
            }
            return combined
        } catch {
            throw StorageError.cryptoFailure
        }
    }

    static func open(_ ciphertext: Data, key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw StorageError.cryptoFailure
        }
    }
}
