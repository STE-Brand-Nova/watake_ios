import Foundation

public protocol DocumentRepository: Sendable {
    func folder(id: UUID) async throws -> Folder?
    func folders() async throws -> [Folder]
    func saveFolder(_ folder: Folder) async throws

    func document(id: UUID) async throws -> StoredDocument?
    func documents(in folderId: UUID) async throws -> [StoredDocument]
    func saveDocument(_ document: StoredDocument) async throws

    func tags() async throws -> [Tag]
    func saveTag(_ tag: Tag) async throws

    func watermarkPresets() async throws -> [WatermarkPreset]
    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws
}

public protocol DocumentAssetStore: Sendable {
    func containsAsset(_ reference: AssetReference) async throws -> Bool
    func removeAsset(_ reference: AssetReference) async throws
}

public protocol DocumentScanning: Sendable {
    func scanDocument(into folderId: UUID, named name: String) async throws -> StoredDocument
}
