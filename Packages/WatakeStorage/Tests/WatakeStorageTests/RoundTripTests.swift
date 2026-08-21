import Foundation
import Testing
import WatakeDomain
@testable import WatakeStorage

@Suite("Folder and document round trips")
struct RoundTripTests {
    @Test("folder create/read/update round trips")
    func folderRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder(name: "Original")
        try await storage.saveFolder(folder)

        let fetched = try await storage.folder(id: folder.id)
        #expect(fetched == folder)

        let updated = makeFolder(id: folder.id, name: "Renamed", createdAt: folder.createdAt)
        try await storage.saveFolder(updated)

        let refetched = try await storage.folder(id: folder.id)
        #expect(refetched?.name == "Renamed")

        let list = try await storage.folders()
        #expect(list.map(\.id) == [folder.id])
    }

    @Test("document create/read/update round trips and orders by orderIndex")
    func documentRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let bytesA = Data("a".utf8)
        let assetA = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytesA)
        try await storage.saveAsset(bytesA, reference: assetA)
        let documentA = makeDocument(folderId: folder.id, orderIndex: 1, source: assetA)
        try await storage.saveDocument(documentA)

        let bytesB = Data("b".utf8)
        let assetB = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: bytesB)
        try await storage.saveAsset(bytesB, reference: assetB)
        let documentB = makeDocument(folderId: folder.id, orderIndex: 0, source: assetB)
        try await storage.saveDocument(documentB)

        let listed = try await storage.documents(in: folder.id)
        #expect(listed.map(\.id) == [documentB.id, documentA.id])

        let updated = makeDocument(
            id: documentA.id,
            folderId: folder.id,
            name: "Renamed",
            orderIndex: 1,
            source: assetA
        )
        try await storage.saveDocument(updated)

        let fetched = try await storage.document(id: documentA.id)
        #expect(fetched?.name == "Renamed")
    }

    @Test("tag and watermark preset round trip")
    func tagAndPresetRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let tag = Tag(id: UUID(), label: "Urgent", colorHex: "#ff0000")
        try await storage.saveTag(tag)
        let tags = try await storage.tags()
        #expect(tags == [tag])

        let config = WatermarkConfig(
            automatic: true,
            globalPosition: .center,
            globalRotation: 0,
            globalOpacity: 0.5
        )
        let preset = WatermarkPreset(
            id: UUID(),
            name: "Company A",
            config: config,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await storage.saveWatermarkPreset(preset)
        let presets = try await storage.watermarkPresets()
        #expect(presets == [preset])
    }

    @Test("watermark presets use stable case-insensitive name order")
    func watermarkPresetOrdering() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)
        let config = WatermarkConfig(automatic: false, globalPosition: .center, globalRotation: 0, globalOpacity: 1)
        let alpha = WatermarkPreset(id: UUID(), name: "Alpha", config: config, createdAt: .now, updatedAt: .now)
        let beta = WatermarkPreset(id: UUID(), name: "beta", config: config, createdAt: .now, updatedAt: .now)
        let zeta = WatermarkPreset(id: UUID(), name: "zeta", config: config, createdAt: .now, updatedAt: .now)

        try await storage.saveWatermarkPreset(zeta)
        try await storage.saveWatermarkPreset(alpha)
        try await storage.saveWatermarkPreset(beta)

        #expect(try await storage.watermarkPresets().map(\.name) == ["Alpha", "beta", "zeta"])
    }

    @Test("recipients are case-insensitively unique and issuance commit round trips")
    func recipientAndIssuanceRoundTrip() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let recipient = WatermarkRecipient(id: UUID(), displayName: "Acme", createdAt: timestamp, updatedAt: timestamp)
        try await storage.saveWatermarkRecipient(recipient)

        let duplicate = WatermarkRecipient(id: UUID(), displayName: "acme", createdAt: timestamp, updatedAt: timestamp)
        await #expect(throws: WatermarkCopyStoreError.duplicateRecipientName) {
            try await storage.saveWatermarkRecipient(duplicate)
        }

        let bytes = Data("rendered-page".utf8)
        let pageID = UUID()
        let renditionID = UUID()
        let reference = AssetReference(
            id: UUID(),
            relativePath: "renditions/\(renditionID.uuidString.lowercased())/pages/\(pageID.uuidString.lowercased()).jpg",
            sha256Hex: sha256Hex(of: bytes),
            byteSize: bytes.count,
            mediaType: "image/jpeg"
        )
        try await storage.saveAsset(bytes, reference: reference)
        let issuance = makeIssuance(
            recipient: recipient,
            timestamp: timestamp,
            reference: reference,
            pageID: pageID,
            renditionID: renditionID
        )
        try await storage.saveWatermarkIssuance(issuance)

        #expect(try await storage.watermarkRecipients() == [recipient])
        #expect(try await storage.watermarkIssuances() == [issuance])
    }

    @Test("concurrent watermark preset saves reject a duplicate name atomically")
    func concurrentWatermarkPresetSavesRejectDuplicateName() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)
        let config = WatermarkConfig(automatic: false, globalPosition: .center, globalRotation: 0, globalOpacity: 1)
        let first = WatermarkPreset(id: UUID(), name: "Company", config: config, createdAt: .now, updatedAt: .now)
        let second = WatermarkPreset(id: UUID(), name: "company", config: config, createdAt: .now, updatedAt: .now)

        async let firstResult = savePreset(first, to: storage)
        async let secondResult = savePreset(second, to: storage)
        let results = await [firstResult, secondResult]

        #expect(results.filter(\.isSuccess).count == 1)
        #expect(results.compactMap(\.duplicateNameError) == [.duplicateName])
        #expect(try await storage.watermarkPresets().count == 1)
    }

    @Test("concurrent recipient saves reject a duplicate name atomically")
    func concurrentRecipientSavesRejectDuplicateName() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)
        let first = WatermarkRecipient(id: UUID(), displayName: "Acme", createdAt: .now, updatedAt: .now)
        let second = WatermarkRecipient(id: UUID(), displayName: "acme", createdAt: .now, updatedAt: .now)

        async let firstResult = saveRecipient(first, to: storage)
        async let secondResult = saveRecipient(second, to: storage)
        let results = await [firstResult, secondResult]

        #expect(results.filter(\.isSuccess).count == 1)
        #expect(results.compactMap(\.duplicateRecipientError) == [.duplicateRecipientName])
        #expect(try await storage.watermarkRecipients().count == 1)
    }

    @Test("concurrent issuance commits allocate distinct recipient-relative versions")
    func concurrentIssuanceCommitsAllocateDistinctVersions() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let recipient = WatermarkRecipient(id: UUID(), displayName: "Acme", createdAt: timestamp, updatedAt: timestamp)
        let documentID = UUID()

        let firstBytes = Data("first-rendered-page".utf8)
        let secondBytes = Data("second-rendered-page".utf8)
        let firstReference = renditionReference(bytes: firstBytes)
        let secondReference = renditionReference(bytes: secondBytes)
        try await storage.saveAsset(firstBytes, reference: firstReference)
        try await storage.saveAsset(secondBytes, reference: secondReference)
        let first = makeIssuance(
            recipient: recipient,
            timestamp: timestamp,
            reference: firstReference,
            pageID: UUID(),
            renditionID: UUID(),
            documentID: documentID
        )
        let second = makeIssuance(
            recipient: recipient,
            timestamp: timestamp,
            reference: secondReference,
            pageID: UUID(),
            renditionID: UUID(),
            documentID: documentID
        )

        async let firstCommit = storage.commitWatermarkIssuance(first, recipient: recipient)
        async let secondCommit = storage.commitWatermarkIssuance(second, recipient: recipient)
        let committed = try await [firstCommit, secondCommit]
        let versions = committed.flatMap(\.renditions).map(\.version).sorted()

        #expect(versions == [1, 2])
    }

    @Test("reassigning a document to a different folder is rejected")
    func folderReassignmentRejected() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folderA = makeFolder()
        let folderB = makeFolder()
        try await storage.saveFolder(folderA)
        try await storage.saveFolder(folderB)

        let bytes = Data("a".utf8)
        let asset = makeAssetReference(folderId: folderA.id, documentId: UUID(), bytes: bytes)
        try await storage.saveAsset(bytes, reference: asset)
        let document = makeDocument(folderId: folderA.id, source: asset)
        try await storage.saveDocument(document)

        let moved = makeDocument(id: document.id, folderId: folderB.id, source: asset)

        await #expect(throws: StorageError.folderReassignmentUnsupported) {
            try await storage.saveDocument(moved)
        }
    }

    @Test("saving a document into a folder that does not exist is rejected")
    func documentRequiresExistingFolder() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let missingFolderId = UUID()
        let asset = makeAssetReference(folderId: missingFolderId, documentId: UUID(), bytes: Data("a".utf8))
        let document = makeDocument(folderId: missingFolderId, source: asset)

        await #expect(throws: StorageError.owningFolderUnavailable) {
            try await storage.saveDocument(document)
        }
    }

    @Test("saving a document into a trashed folder is rejected")
    func documentRequiresNonTrashedFolder() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let trashedFolder = makeFolder(deletedAt: Date(timeIntervalSince1970: 1_700_000_500))
        try await storage.saveFolder(trashedFolder)

        let asset = makeAssetReference(folderId: trashedFolder.id, documentId: UUID(), bytes: Data("a".utf8))
        let document = makeDocument(folderId: trashedFolder.id, source: asset)

        await #expect(throws: StorageError.owningFolderUnavailable) {
            try await storage.saveDocument(document)
        }
    }

    @Test("saving a document whose page source asset was never written is rejected")
    func documentRequiresExistingSourceAsset() async throws {
        let root = EphemeralRootResolver()
        defer { root.removeAll() }
        let service = makeTestKeychainService()
        defer { deleteTestKeychainKey(service: service) }
        let storage = makeStorage(root: root, service: service)

        let folder = makeFolder()
        try await storage.saveFolder(folder)

        let neverSavedAsset = makeAssetReference(folderId: folder.id, documentId: UUID(), bytes: Data("a".utf8))
        let document = makeDocument(folderId: folder.id, source: neverSavedAsset)

        await #expect(throws: StorageError.notFound) {
            try await storage.saveDocument(document)
        }

        let stored = try await storage.document(id: document.id)
        #expect(stored == nil)
    }
}

private func makeIssuance(
    recipient: WatermarkRecipient,
    timestamp: Date,
    reference: AssetReference,
    pageID: UUID,
    renditionID: UUID,
    documentID: UUID = UUID()
) -> WatermarkIssuance {
    let config = WatermarkConfig(
        automatic: false,
        body: WatermarkTextLayer(
            text: "For Acme", enabled: true, fontName: "Helvetica", sizePreset: .medium,
            colorHex: "#0B1220", rotation: 0, opacity: 0.5
        ),
        globalPosition: .center,
        globalRotation: 0,
        globalOpacity: 1
    )
    return WatermarkIssuance(
        id: UUID(),
        recipientId: recipient.id,
        recipientNameSnapshot: recipient.displayName,
        purpose: "Hiring",
        templateConfig: config,
        renditions: [WatermarkRendition(
            id: renditionID,
            documentId: documentID,
            originalNameSnapshot: "Diploma",
            version: 1,
            config: config,
            pages: [RenditionPage(id: UUID(), pageId: pageID, index: 0, watermarked: reference)],
            createdAt: timestamp
        )],
        createdAt: timestamp
    )
}

private func renditionReference(bytes: Data) -> AssetReference {
    let renditionID = UUID()
    let pageID = UUID()
    return AssetReference(
        id: UUID(),
        relativePath: "renditions/\(renditionID.uuidString.lowercased())/pages/\(pageID.uuidString.lowercased()).jpg",
        sha256Hex: sha256Hex(of: bytes),
        byteSize: bytes.count,
        mediaType: "image/jpeg"
    )
}

private func savePreset(_ preset: WatermarkPreset, to storage: WatakeFileStorage) async -> Result<Void, Error> {
    do {
        try await storage.saveWatermarkPreset(preset)
        return .success(())
    } catch {
        return .failure(error)
    }
}

private func saveRecipient(_ recipient: WatermarkRecipient, to storage: WatakeFileStorage) async -> Result<Void, Error> {
    do {
        try await storage.saveWatermarkRecipient(recipient)
        return .success(())
    } catch {
        return .failure(error)
    }
}

extension Result where Success == Void, Failure == Error {
    fileprivate var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    fileprivate var duplicateNameError: WatermarkPresetStoreError? {
        guard case .failure(let error) = self else { return nil }
        return error as? WatermarkPresetStoreError
    }

    fileprivate var duplicateRecipientError: WatermarkCopyStoreError? {
        guard case .failure(let error) = self else { return nil }
        return error as? WatermarkCopyStoreError
    }
}
