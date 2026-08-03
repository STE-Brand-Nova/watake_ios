import CryptoKit
import Foundation
import WatakeDomain

public actor WatakeFileStorage {
    private let rootResolver: StorageRootResolving
    private let protectionApplier: FileProtectionApplying
    private let encryptionKeyStore: EncryptionKeyStoring
    private let fileManager: FileManager

    private var cachedRoot: URL?
    private var cachedKey: SymmetricKey?
    private var isPrepared = false

    public init(
        rootResolver: StorageRootResolving,
        protectionApplier: FileProtectionApplying,
        encryptionKeyStore: EncryptionKeyStoring,
        fileManager: FileManager = .default
    ) {
        self.rootResolver = rootResolver
        self.protectionApplier = protectionApplier
        self.encryptionKeyStore = encryptionKeyStore
        self.fileManager = fileManager
    }

    public func prepare() throws {
        let root = try resolvedRoot()
        try createDirectoryIfNeeded(StorageLayout.foldersRoot(root))
        try createDirectoryIfNeeded(StorageLayout.tagsRoot(root))
        try createDirectoryIfNeeded(StorageLayout.presetsRoot(root))
        TemporaryFileCleanup.removeStaleTemporaryFiles(under: root, fileManager: fileManager)
        _ = try encryptionKey()
        isPrepared = true
    }

    private func ensurePrepared() throws {
        guard !isPrepared else {
            return
        }
        try prepare()
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw StorageError.ioFailure
        }
    }

    private func resolvedRoot() throws -> URL {
        if let cachedRoot {
            return cachedRoot
        }
        let root = try rootResolver.resolveRoot()
        cachedRoot = root
        return root
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let cachedKey {
            return cachedKey
        }
        do {
            let key = try encryptionKeyStore.loadOrCreateEncryptionKey()
            cachedKey = key
            return key
        } catch {
            throw StorageError.keychainUnavailable
        }
    }

    private func writer(root: URL) -> AtomicFileWriter {
        AtomicFileWriter(
            fileManager: fileManager,
            protectionApplier: protectionApplier,
            temporaryDirectory: StorageLayout.temporaryDirectory(root)
        )
    }

    private func readEncryptedRecord<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let ciphertext: Data
        do {
            ciphertext = try Data(contentsOf: url)
        } catch {
            throw StorageError.ioFailure
        }
        let plaintext = try CryptoBox.open(ciphertext, key: encryptionKey())
        do {
            return try WatakeContractCoding.makeJSONDecoder().decode(type, from: plaintext)
        } catch {
            throw StorageError.invalidRecord
        }
    }

    private func readFolder(at url: URL) throws -> Folder? {
        guard let value = try readEncryptedRecord(Folder.self, at: url) else {
            return nil
        }
        try validated(value.validate)
        return value
    }

    private func readDocument(at url: URL) throws -> StoredDocument? {
        guard let value = try readEncryptedRecord(StoredDocument.self, at: url) else {
            return nil
        }
        try validated(value.validate)
        return value
    }

    private func readTag(at url: URL) throws -> Tag? {
        guard let value = try readEncryptedRecord(Tag.self, at: url) else {
            return nil
        }
        try validated(value.validate)
        return value
    }

    private func readPreset(at url: URL) throws -> WatermarkPreset? {
        guard let value = try readEncryptedRecord(WatermarkPreset.self, at: url) else {
            return nil
        }
        try validated(value.validate)
        return value
    }

    private func validated(_ validate: () throws -> Void) throws {
        do {
            try validate()
        } catch is DomainValidationError {
            throw StorageError.invalidRecord
        }
    }

    private func writeEncryptedRecord(_ value: some Encodable, to url: URL, root: URL) throws {
        let plaintext: Data
        do {
            plaintext = try WatakeContractCoding.makeJSONEncoder().encode(value)
        } catch {
            throw StorageError.encodingFailed
        }
        let ciphertext = try CryptoBox.seal(plaintext, key: encryptionKey())
        try writer(root: root).write(ciphertext, to: url)
    }

    private func listRecordIDs(in directory: URL, fileExtension: String? = nil) throws -> [UUID] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            throw StorageError.ioFailure
        }
        return contents.compactMap { url in
            let name = fileExtension.map { url.lastPathComponent.replacingOccurrences(of: $0, with: "") }
                ?? url.lastPathComponent
            return UUID(uuidString: name)
        }
    }

    private func locateDocumentFolder(id: UUID, root: URL) throws -> UUID? {
        let folderIds = try listRecordIDs(in: StorageLayout.foldersRoot(root))
        for folderId in folderIds where fileManager.fileExists(
            atPath: StorageLayout.documentMetadataFile(root, folderId, id).path
        ) {
            return folderId
        }
        return nil
    }
}

extension WatakeFileStorage: DocumentRepository {
    public func folder(id: UUID) async throws -> Folder? {
        try ensurePrepared()
        let root = try resolvedRoot()
        return try readFolder(at: StorageLayout.folderMetadataFile(root, id))
    }

    public func folders() async throws -> [Folder] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let ids = try listRecordIDs(in: StorageLayout.foldersRoot(root))
        let folders = try ids.compactMap {
            try readFolder(at: StorageLayout.folderMetadataFile(root, $0))
        }
        return folders.sorted { lhs, rhs in
            lhs.createdAt != rhs.createdAt
                ? lhs.createdAt < rhs.createdAt
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func saveFolder(_ folder: Folder) async throws {
        try ensurePrepared()
        try folder.validate()
        let root = try resolvedRoot()
        try writeEncryptedRecord(folder, to: StorageLayout.folderMetadataFile(root, folder.id), root: root)
    }

    public func document(id: UUID) async throws -> StoredDocument? {
        try ensurePrepared()
        let root = try resolvedRoot()
        guard let folderId = try locateDocumentFolder(id: id, root: root) else {
            return nil
        }
        return try readDocument(at: StorageLayout.documentMetadataFile(root, folderId, id))
    }

    public func documents(in folderId: UUID) async throws -> [StoredDocument] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let ids = try listRecordIDs(in: StorageLayout.documentsRoot(root, folderId))
        let documents = try ids.compactMap {
            try readDocument(at: StorageLayout.documentMetadataFile(root, folderId, $0))
        }
        return documents.sorted { lhs, rhs in
            lhs.orderIndex != rhs.orderIndex
                ? lhs.orderIndex < rhs.orderIndex
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func saveDocument(_ document: StoredDocument) async throws {
        try ensurePrepared()
        try document.validate()
        let root = try resolvedRoot()
        let owningFolder = try readFolder(at: StorageLayout.folderMetadataFile(root, document.folderId))
        guard let owningFolder, owningFolder.deletedAt == nil else {
            throw StorageError.owningFolderUnavailable
        }
        for page in document.pages {
            _ = try await readAsset(page.source)
            if let rectified = page.rectified {
                _ = try await readAsset(rectified)
            }
        }
        let existingFolderId = try locateDocumentFolder(id: document.id, root: root)
        if let existingFolderId, existingFolderId != document.folderId {
            throw StorageError.folderReassignmentUnsupported
        }
        try writeEncryptedRecord(
            document,
            to: StorageLayout.documentMetadataFile(root, document.folderId, document.id),
            root: root
        )
    }

    public func deleteDocument(id: UUID) async throws {
        try ensurePrepared()
        let root = try resolvedRoot()
        guard let folderId = try locateDocumentFolder(id: id, root: root) else {
            throw StorageError.notFound
        }
        let metadataURL = StorageLayout.documentMetadataFile(root, folderId, id)
        guard let existing = try readDocument(at: metadataURL) else {
            throw StorageError.notFound
        }
        guard existing.deletedAt != nil else {
            throw StorageError.documentNotInTrash
        }
        for page in existing.pages {
            try await removeAsset(page.source)
            if let rectified = page.rectified {
                try await removeAsset(rectified)
            }
        }
        let directory = StorageLayout.documentDirectory(root, folderId, id)
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw StorageError.ioFailure
        }
    }

    public func tags() async throws -> [Tag] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let ids = try listRecordIDs(in: StorageLayout.tagsRoot(root), fileExtension: ".json.enc")
        let tags = try ids.compactMap {
            try readTag(at: StorageLayout.tagMetadataFile(root, $0))
        }
        return tags.sorted { lhs, rhs in
            let lhsLabel = lhs.label.lowercased()
            let rhsLabel = rhs.label.lowercased()
            return lhsLabel != rhsLabel
                ? lhsLabel < rhsLabel
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func saveTag(_ tag: Tag) async throws {
        try ensurePrepared()
        try tag.validate()
        let root = try resolvedRoot()
        try writeEncryptedRecord(tag, to: StorageLayout.tagMetadataFile(root, tag.id), root: root)
    }

    public func watermarkPresets() async throws -> [WatermarkPreset] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let ids = try listRecordIDs(in: StorageLayout.presetsRoot(root), fileExtension: ".json.enc")
        let presets = try ids.compactMap {
            try readPreset(at: StorageLayout.presetMetadataFile(root, $0))
        }
        return presets.sorted { lhs, rhs in
            lhs.createdAt != rhs.createdAt
                ? lhs.createdAt < rhs.createdAt
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {
        try ensurePrepared()
        try preset.validate()
        let root = try resolvedRoot()
        try writeEncryptedRecord(preset, to: StorageLayout.presetMetadataFile(root, preset.id), root: root)
    }
}

extension WatakeFileStorage: DocumentAssetStore {
    public func saveAsset(_ data: Data, reference: AssetReference) async throws {
        try ensurePrepared()
        try reference.validate()
        guard data.count == reference.byteSize, sha256Hex(of: data) == reference.sha256Hex else {
            throw StorageError.assetIntegrityMismatch
        }
        let root = try resolvedRoot()
        try writer(root: root).write(data, to: StorageLayout.assetFile(root, reference.relativePath))
    }

    public func readAsset(_ reference: AssetReference) async throws -> Data {
        try ensurePrepared()
        try reference.validate()
        let root = try resolvedRoot()
        let path = StorageLayout.assetFile(root, reference.relativePath)
        guard fileManager.fileExists(atPath: path.path) else {
            throw StorageError.notFound
        }
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw StorageError.ioFailure
        }
        guard data.count == reference.byteSize, sha256Hex(of: data) == reference.sha256Hex else {
            throw StorageError.assetIntegrityMismatch
        }
        return data
    }

    public func containsAsset(_ reference: AssetReference) async throws -> Bool {
        try ensurePrepared()
        try reference.validate()
        let root = try resolvedRoot()
        return fileManager.fileExists(atPath: StorageLayout.assetFile(root, reference.relativePath).path)
    }

    public func removeAsset(_ reference: AssetReference) async throws {
        try ensurePrepared()
        try reference.validate()
        let root = try resolvedRoot()
        let path = StorageLayout.assetFile(root, reference.relativePath)
        guard fileManager.fileExists(atPath: path.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: path)
        } catch {
            throw StorageError.ioFailure
        }
    }

    private func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// `document(id:)` and `readAsset(_:)` already satisfy this narrower port via
/// the `DocumentRepository`/`DocumentAssetStore` conformances above.
extension WatakeFileStorage: DocumentPageAssetLoading {}
