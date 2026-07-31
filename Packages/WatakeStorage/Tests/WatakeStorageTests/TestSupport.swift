import CryptoKit
import Foundation
import Security
import WatakeDomain
@testable import WatakeStorage

struct EphemeralRootResolver: StorageRootResolving {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("watake-storage-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func resolveRoot() throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}

final class RecordingFileProtectionApplier: FileProtectionApplying, @unchecked Sendable {
    private let lock = NSLock()
    private var _protectedURLs: [URL] = []
    var shouldFail = false

    var protectedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _protectedURLs
    }

    func applyProtection(at url: URL) throws {
        lock.lock()
        let fail = shouldFail
        if !fail {
            _protectedURLs.append(url)
        }
        lock.unlock()
        if fail {
            throw StorageError.ioFailure
        }
    }
}

func makeTestKeychainService() -> String {
    "com.watake.storage.tests.\(UUID().uuidString)"
}

func deleteTestKeychainKey(service: String, account: String = "encryption-key") {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
}

func makeStorage(
    root: EphemeralRootResolver,
    protectionApplier: FileProtectionApplying = RecordingFileProtectionApplier(),
    service: String
) -> WatakeFileStorage {
    WatakeFileStorage(
        rootResolver: root,
        protectionApplier: protectionApplier,
        encryptionKeyStore: KeychainEncryptionKeyStore(service: service)
    )
}

func makeFolder(
    id: UUID = UUID(),
    name: String = "Transcripts",
    colorHex: String = "#112233",
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    deletedAt: Date? = nil
) -> Folder {
    Folder(id: id, name: name, colorHex: colorHex, createdAt: createdAt, deletedAt: deletedAt)
}

func makeAssetReference(
    id: UUID = UUID(),
    folderId: UUID,
    documentId: UUID,
    pageId: UUID = UUID(),
    kind: String = "source",
    bytes: Data
) -> AssetReference {
    let digest = sha256Hex(of: bytes)
    let path = [
        "folders/\(folderId.uuidString.lowercased())",
        "documents/\(documentId.uuidString.lowercased())",
        "pages/\(pageId.uuidString.lowercased())",
        "\(kind).bin"
    ].joined(separator: "/")
    return AssetReference(
        id: id,
        relativePath: path,
        sha256Hex: digest,
        byteSize: bytes.count,
        mediaType: "application/octet-stream"
    )
}

func makeDocument(
    id: UUID = UUID(),
    folderId: UUID,
    name: String = "Diploma",
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    orderIndex: Int = 0,
    source: AssetReference,
    deletedAt: Date? = nil
) -> StoredDocument {
    let page = DocumentPage(id: UUID(), index: 0, source: source)
    return StoredDocument(
        id: id,
        folderId: folderId,
        name: name,
        createdAt: createdAt,
        updatedAt: updatedAt,
        orderIndex: orderIndex,
        pages: [page],
        deletedAt: deletedAt
    )
}

func sha256Hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
