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
        try createDirectoryIfNeeded(StorageLayout.recipientsRoot(root))
        try createDirectoryIfNeeded(StorageLayout.issuancesRoot(root))
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

    /// `owningFolderId` and `root` let this self-heal a document whose
    /// `folderId` field disagrees with the folder it physically lives under.
    /// `locateDocumentFolder` treats physical location as the ownership
    /// source of truth (see `moveDocument`), so that mismatch is corrected
    /// here rather than trusted. A failed correction write is not data loss:
    /// the caller still gets the correct value, and the next read retries.
    private func readDocument(at url: URL, owningFolderId: UUID, root: URL) throws -> StoredDocument? {
        guard let value = try readEncryptedRecord(StoredDocument.self, at: url) else {
            return nil
        }
        try validated(value.validate)
        guard value.folderId != owningFolderId else {
            return value
        }
        let corrected = StoredDocument(
            id: value.id,
            folderId: owningFolderId,
            name: value.name,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt,
            orderIndex: value.orderIndex,
            pages: value.pages,
            deletedAt: value.deletedAt,
            tagIds: value.tagIds,
            watermarkPresetId: value.watermarkPresetId
        )
        try? writeEncryptedRecord(corrected, to: url, root: root)
        return corrected
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

    private func readRecipient(at url: URL) throws -> WatermarkRecipient? {
        guard let value = try readEncryptedRecord(WatermarkRecipient.self, at: url) else { return nil }
        try validated(value.validate)
        return value
    }

    private func readIssuance(at url: URL) throws -> WatermarkIssuance? {
        guard let value = try readEncryptedRecord(WatermarkIssuance.self, at: url) else { return nil }
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
        return try readDocument(at: StorageLayout.documentMetadataFile(root, folderId, id), owningFolderId: folderId, root: root)
    }

    public func documents(in folderId: UUID) async throws -> [StoredDocument] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let ids = try listRecordIDs(in: StorageLayout.documentsRoot(root, folderId))
        let documents = try ids.compactMap {
            try readDocument(at: StorageLayout.documentMetadataFile(root, folderId, $0), owningFolderId: folderId, root: root)
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

    /// Persists `document` under its new `folderId`, unlike `saveDocument`
    /// which rejects any folder change to an existing document. Asset bytes
    /// are content-addressed and not folder-scoped, so only the per-folder
    /// metadata directory moves.
    ///
    /// Relocates the directory with a single `moveItem` (an atomic rename on
    /// the same volume — the whole storage tree is under one root), then
    /// rewrites `document.json.enc` in place with the corrected `folderId`.
    /// `locateDocumentFolder` treats physical location, not the persisted
    /// `folderId` field, as ownership truth, so a crash between those two
    /// steps cannot lose or duplicate the document: it is already
    /// discoverable at the destination, and `readDocument` self-heals the
    /// stale field on the next read. There is no unguarded `try?` around a
    /// step whose failure would change what "moved" means.
    public func moveDocument(_ document: StoredDocument) async throws {
        try ensurePrepared()
        try document.validate()
        let root = try resolvedRoot()
        let owningFolder = try readFolder(at: StorageLayout.folderMetadataFile(root, document.folderId))
        guard let owningFolder, owningFolder.deletedAt == nil else {
            throw StorageError.owningFolderUnavailable
        }
        guard let existingFolderId = try locateDocumentFolder(id: document.id, root: root) else {
            throw StorageError.notFound
        }
        for page in document.pages {
            _ = try await readAsset(page.source)
            if let rectified = page.rectified {
                _ = try await readAsset(rectified)
            }
        }
        guard existingFolderId != document.folderId else {
            try writeEncryptedRecord(
                document,
                to: StorageLayout.documentMetadataFile(root, document.folderId, document.id),
                root: root
            )
            return
        }
        let oldDirectory = StorageLayout.documentDirectory(root, existingFolderId, document.id)
        let newDirectory = StorageLayout.documentDirectory(root, document.folderId, document.id)
        do {
            try fileManager.createDirectory(
                at: StorageLayout.documentsRoot(root, document.folderId), withIntermediateDirectories: true
            )
        } catch {
            throw StorageError.ioFailure
        }
        do {
            try fileManager.moveItem(at: oldDirectory, to: newDirectory)
        } catch {
            throw StorageError.ioFailure
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
        guard let existing = try readDocument(at: metadataURL, owningFolderId: folderId, root: root) else {
            throw StorageError.notFound
        }
        let folderMetadataURL = StorageLayout.folderMetadataFile(root, folderId)
        let folderIsTrashed = try (readFolder(at: folderMetadataURL))?.deletedAt != nil
        guard existing.deletedAt != nil || folderIsTrashed else {
            throw StorageError.documentNotInTrash
        }
        for page in existing.pages {
            if try await !hasOtherReferences(to: page.source, excludingDocumentId: id) {
                try await removeAsset(page.source)
            }
            if let rectified = page.rectified {
                if try await !hasOtherReferences(to: rectified, excludingDocumentId: id) {
                    try await removeAsset(rectified)
                }
            }
        }
        let directory = StorageLayout.documentDirectory(root, folderId, id)
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw StorageError.ioFailure
        }
    }

    public func deleteFolder(id: UUID) async throws {
        try ensurePrepared()
        let root = try resolvedRoot()
        let metadataURL = StorageLayout.folderMetadataFile(root, id)
        guard let existing = try readFolder(at: metadataURL) else {
            throw StorageError.notFound
        }
        guard existing.deletedAt != nil else {
            throw StorageError.folderNotInTrash
        }
        let childIdsList = try listRecordIDs(in: StorageLayout.documentsRoot(root, id))
        let childIds = Set(childIdsList)
        for childId in childIdsList {
            if let doc = try readDocument(at: StorageLayout.documentMetadataFile(root, id, childId), owningFolderId: id, root: root) {
                for page in doc.pages {
                    if try await !hasOtherReferences(to: page.source, excludingDocumentIds: childIds) {
                        try await removeAsset(page.source)
                    }
                    if let rectified = page.rectified {
                        if try await !hasOtherReferences(to: rectified, excludingDocumentIds: childIds) {
                            try await removeAsset(rectified)
                        }
                    }
                }
            }
        }
        let directory = StorageLayout.documentsRoot(root, id)
        do {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try fileManager.removeItem(at: metadataURL)
        } catch {
            throw StorageError.ioFailure
        }
    }

    public func trashedFolders() async throws -> [Folder] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let ids = try listRecordIDs(in: StorageLayout.foldersRoot(root))
        let folders = try ids.compactMap {
            try readFolder(at: StorageLayout.folderMetadataFile(root, $0))
        }
        return folders.filter { $0.deletedAt != nil }
    }

    public func trashedDocuments() async throws -> [StoredDocument] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let folderIds = try listRecordIDs(in: StorageLayout.foldersRoot(root))
        var trashed: [StoredDocument] = []
        for folderId in folderIds {
            let ids = try listRecordIDs(in: StorageLayout.documentsRoot(root, folderId))
            for id in ids {
                if let doc = try readDocument(
                    at: StorageLayout.documentMetadataFile(root, folderId, id),
                    owningFolderId: folderId,
                    root: root
                ), doc.deletedAt != nil {
                    trashed.append(doc)
                }
            }
        }
        return trashed
    }

    public func hasOtherReferences(to asset: AssetReference, excludingDocumentId: UUID) async throws -> Bool {
        try await hasOtherReferences(to: asset, excludingDocumentIds: [excludingDocumentId])
    }

    public func hasOtherReferences(to asset: AssetReference, excludingDocumentIds: Set<UUID>) async throws -> Bool {
        try referencedAssetIDs(excludingDocumentIds: excludingDocumentIds).contains(asset.id)
    }

    /// Builds the complete live asset-reference set in one decrypt/parse pass.
    /// Destructive batch operations use this once, rather than rescanning the
    /// entire archive for every candidate page or logo.
    public func referencedAssetIDs(excludingDocumentIds: Set<UUID> = []) throws -> Set<UUID> {
        try ensurePrepared()
        let root = try resolvedRoot()
        var references: Set<UUID> = []
        let folderIds = try listRecordIDs(in: StorageLayout.foldersRoot(root))
        for folderId in folderIds {
            let documentIds = try listRecordIDs(in: StorageLayout.documentsRoot(root, folderId))
            for documentId in documentIds where !excludingDocumentIds.contains(documentId) {
                if let doc = try readDocument(
                    at: StorageLayout.documentMetadataFile(root, folderId, documentId),
                    owningFolderId: folderId,
                    root: root
                ) {
                    references.formUnion(assetIDs(in: doc))
                }
            }
        }
        let presetIDs = try listRecordIDs(in: StorageLayout.presetsRoot(root), fileExtension: ".json.enc")
        for preset in try presetIDs.compactMap({ try readPreset(at: StorageLayout.presetMetadataFile(root, $0)) }) {
            if let image = preset.config.image {
                references.insert(image.assetRef.id)
            }
        }
        let issuanceIDs = try listRecordIDs(in: StorageLayout.issuancesRoot(root), fileExtension: ".json.enc")
        for issuance in try issuanceIDs.compactMap({ try readIssuance(at: StorageLayout.issuanceMetadataFile(root, $0)) }) {
            references.formUnion(assetIDs(in: issuance))
        }
        return references
    }

    private func assetIDs(in document: StoredDocument) -> Set<UUID> {
        document.pages.reduce(into: []) { references, page in
            references.insert(page.source.id)
            if let rectified = page.rectified {
                references.insert(rectified.id)
            }
        }
    }

    private func assetIDs(in issuance: WatermarkIssuance) -> Set<UUID> {
        var references = Set(issuance.templateConfig.image.map { [$0.assetRef.id] } ?? [])
        for rendition in issuance.renditions {
            if let image = rendition.config.image {
                references.insert(image.assetRef.id)
            }
            rendition.pages.forEach { references.insert($0.watermarked.id) }
        }
        return references
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
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return nameOrder == .orderedSame
                ? lhs.id.uuidString < rhs.id.uuidString
                : nameOrder == .orderedAscending
        }
    }

    public func saveWatermarkPreset(_ preset: WatermarkPreset) async throws {
        try ensurePrepared()
        try preset.validate()
        let root = try resolvedRoot()

        // This actor-isolated read-and-write transaction prevents concurrent
        // callers from persisting case-insensitive duplicate names. An update
        // to the same record remains valid.
        let ids = try listRecordIDs(in: StorageLayout.presetsRoot(root), fileExtension: ".json.enc")
        let hasDuplicateName = try ids
            .compactMap { try readPreset(at: StorageLayout.presetMetadataFile(root, $0)) }
            .contains {
                $0.id != preset.id && $0.name.caseInsensitiveCompare(preset.name) == .orderedSame
            }
        guard !hasDuplicateName else {
            throw WatermarkPresetStoreError.duplicateName
        }
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
        try readValidatedAsset(reference)
    }

    private func readValidatedAsset(_ reference: AssetReference) throws -> Data {
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

extension WatakeFileStorage: WatermarkPresetStore {}

extension WatakeFileStorage: WatermarkCopyRepository {
    public func watermarkRecipients() async throws -> [WatermarkRecipient] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let ids = try listRecordIDs(in: StorageLayout.recipientsRoot(root), fileExtension: ".json.enc")
        return try ids.compactMap { try readRecipient(at: StorageLayout.recipientMetadataFile(root, $0)) }
            .sorted {
                let order = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
            }
    }

    public func saveWatermarkRecipient(_ recipient: WatermarkRecipient) async throws {
        try ensurePrepared()
        let root = try resolvedRoot()
        try persistWatermarkRecipient(recipient, root: root)
    }

    private func persistWatermarkRecipient(_ recipient: WatermarkRecipient, root: URL) throws {
        try recipient.validate()
        // Keep the uniqueness check and write in one actor-isolated,
        // non-suspending transaction.
        let ids = try listRecordIDs(in: StorageLayout.recipientsRoot(root), fileExtension: ".json.enc")
        let hasDuplicateName = try ids
            .compactMap { try readRecipient(at: StorageLayout.recipientMetadataFile(root, $0)) }
            .contains {
                $0.id != recipient.id && $0.displayName.caseInsensitiveCompare(recipient.displayName) == .orderedSame
            }
        guard !hasDuplicateName else {
            throw WatermarkCopyStoreError.duplicateRecipientName
        }
        try writeEncryptedRecord(recipient, to: StorageLayout.recipientMetadataFile(root, recipient.id), root: root)
    }

    public func watermarkIssuances() async throws -> [WatermarkIssuance] {
        try ensurePrepared()
        let root = try resolvedRoot()
        let ids = try listRecordIDs(in: StorageLayout.issuancesRoot(root), fileExtension: ".json.enc")
        return try ids.compactMap { try readIssuance(at: StorageLayout.issuanceMetadataFile(root, $0)) }
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id.uuidString < $1.id.uuidString }
    }

    /// Metadata is the issuance commit marker. Callers stage and integrity-check
    /// every referenced asset before this write, so readers either see the
    /// whole batch or no batch at all.
    public func saveWatermarkIssuance(_ issuance: WatermarkIssuance) async throws {
        try ensurePrepared()
        let root = try resolvedRoot()
        try persistWatermarkIssuance(issuance, root: root)
    }

    private func persistWatermarkIssuance(_ issuance: WatermarkIssuance, root: URL) throws {
        try issuance.validate()
        for rendition in issuance.renditions {
            for page in rendition.pages {
                _ = try readValidatedAsset(page.watermarked)
            }
        }
        if let image = issuance.templateConfig.image, image.enabled {
            _ = try readValidatedAsset(image.assetRef)
        }
        try writeEncryptedRecord(issuance, to: StorageLayout.issuanceMetadataFile(root, issuance.id), root: root)
    }

    public func commitWatermarkIssuance(
        _ issuance: WatermarkIssuance,
        recipient: WatermarkRecipient
    ) async throws -> WatermarkIssuance {
        try ensurePrepared()
        let root = try resolvedRoot()
        let recipientURL = StorageLayout.recipientMetadataFile(root, recipient.id)
        let recipientAlreadyExisted = fileManager.fileExists(atPath: recipientURL.path)
        do {
            // This entire read/allocate/write path is non-suspending inside the
            // storage actor, so separate issuance-service instances cannot
            // publish the same recipient/document version.
            try persistWatermarkRecipient(recipient, root: root)
            let committed = try assigningCommittedVersions(
                to: issuance,
                recipientID: recipient.id,
                root: root
            )
            try persistWatermarkIssuance(committed, root: root)
            return committed
        } catch {
            if !recipientAlreadyExisted {
                try? fileManager.removeItem(at: recipientURL)
            }
            throw error
        }
    }

    private func assigningCommittedVersions(
        to issuance: WatermarkIssuance,
        recipientID: UUID,
        root: URL
    ) throws -> WatermarkIssuance {
        let ids = try listRecordIDs(in: StorageLayout.issuancesRoot(root), fileExtension: ".json.enc")
        let existing = try ids.compactMap { try readIssuance(at: StorageLayout.issuanceMetadataFile(root, $0)) }
        var versions = existing
            .filter { $0.id != issuance.id && $0.recipientId == recipientID }
            .flatMap(\.renditions)
            .reduce(into: [UUID: Int]()) { values, rendition in
                values[rendition.documentId] = max(values[rendition.documentId] ?? 0, rendition.version)
            }
        let renditions = issuance.renditions.map { rendition in
            let version = (versions[rendition.documentId] ?? 0) + 1
            versions[rendition.documentId] = version
            return WatermarkRendition(
                id: rendition.id,
                documentId: rendition.documentId,
                issuanceId: rendition.issuanceId,
                originalNameSnapshot: rendition.originalNameSnapshot,
                version: version,
                config: rendition.config,
                pages: rendition.pages,
                createdAt: rendition.createdAt,
                deletedAt: rendition.deletedAt
            )
        }
        return WatermarkIssuance(
            id: issuance.id,
            recipientId: issuance.recipientId,
            recipientNameSnapshot: issuance.recipientNameSnapshot,
            purpose: issuance.purpose,
            templateConfig: issuance.templateConfig,
            renditions: renditions,
            createdAt: issuance.createdAt
        )
    }

    public func removeWatermarkIssuance(id: UUID) async throws {
        try ensurePrepared()
        let root = try resolvedRoot()
        let path = StorageLayout.issuanceMetadataFile(root, id)
        guard fileManager.fileExists(atPath: path.path) else { return }
        do {
            try fileManager.removeItem(at: path)
        } catch {
            throw StorageError.ioFailure
        }
    }
}

/// `document(id:)` and `readAsset(_:)` already satisfy this narrower port via
/// the `DocumentRepository`/`DocumentAssetStore` conformances above.
extension WatakeFileStorage: DocumentPageAssetLoading {}

/// OCR uses the same encrypted record transaction as every other document
/// metadata update. No OCR content is written outside app-controlled storage.
extension WatakeFileStorage: DocumentOCRPersisting {}
