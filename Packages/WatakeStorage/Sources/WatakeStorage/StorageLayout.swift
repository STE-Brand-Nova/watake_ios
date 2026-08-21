import Foundation

enum StorageLayout {
    static func foldersRoot(_ root: URL) -> URL {
        root.appendingPathComponent("folders", isDirectory: true)
    }

    static func folderDirectory(_ root: URL, _ folderId: UUID) -> URL {
        foldersRoot(root).appendingPathComponent(folderId.uuidString.lowercased(), isDirectory: true)
    }

    static func folderMetadataFile(_ root: URL, _ folderId: UUID) -> URL {
        folderDirectory(root, folderId).appendingPathComponent("folder.json.enc", isDirectory: false)
    }

    static func documentsRoot(_ root: URL, _ folderId: UUID) -> URL {
        folderDirectory(root, folderId).appendingPathComponent("documents", isDirectory: true)
    }

    static func documentDirectory(_ root: URL, _ folderId: UUID, _ documentId: UUID) -> URL {
        documentsRoot(root, folderId).appendingPathComponent(documentId.uuidString.lowercased(), isDirectory: true)
    }

    static func documentMetadataFile(_ root: URL, _ folderId: UUID, _ documentId: UUID) -> URL {
        documentDirectory(root, folderId, documentId).appendingPathComponent("document.json.enc", isDirectory: false)
    }

    static func tagsRoot(_ root: URL) -> URL {
        root.appendingPathComponent("tags", isDirectory: true)
    }

    static func tagMetadataFile(_ root: URL, _ tagId: UUID) -> URL {
        tagsRoot(root).appendingPathComponent("\(tagId.uuidString.lowercased()).json.enc", isDirectory: false)
    }

    static func presetsRoot(_ root: URL) -> URL {
        root.appendingPathComponent("presets", isDirectory: true)
    }

    static func presetMetadataFile(_ root: URL, _ presetId: UUID) -> URL {
        presetsRoot(root).appendingPathComponent("\(presetId.uuidString.lowercased()).json.enc", isDirectory: false)
    }

    static func recipientsRoot(_ root: URL) -> URL {
        root.appendingPathComponent("watermark-recipients", isDirectory: true)
    }

    static func recipientMetadataFile(_ root: URL, _ recipientId: UUID) -> URL {
        recipientsRoot(root).appendingPathComponent("\(recipientId.uuidString.lowercased()).json.enc")
    }

    static func issuancesRoot(_ root: URL) -> URL {
        root.appendingPathComponent("watermark-issuances", isDirectory: true)
    }

    static func issuanceMetadataFile(_ root: URL, _ issuanceId: UUID) -> URL {
        issuancesRoot(root).appendingPathComponent("\(issuanceId.uuidString.lowercased()).json.enc")
    }

    static func assetsRoot(_ root: URL) -> URL {
        root.appendingPathComponent("assets", isDirectory: true)
    }

    static func assetFile(_ root: URL, _ relativePath: String) -> URL {
        assetsRoot(root).appendingPathComponent(relativePath)
    }

    static func temporaryDirectory(_ root: URL) -> URL {
        root.appendingPathComponent(".watake-tmp", isDirectory: true)
    }
}
