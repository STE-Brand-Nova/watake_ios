import Foundation

public protocol DocumentRepository: Sendable {
    func folder(id: UUID) async throws -> Folder?
    func folders() async throws -> [Folder]
    func saveFolder(_ folder: Folder) async throws

    func document(id: UUID) async throws -> StoredDocument?
    func documents(in folderId: UUID) async throws -> [StoredDocument]
    func saveDocument(_ document: StoredDocument) async throws
    func deleteDocument(id: UUID) async throws
    /// Persists a document under its (already-changed) `folderId`, unlike
    /// `saveDocument` which rejects any folder change to a document that
    /// already exists. Callers must supply the complete target record;
    /// implementations move metadata only — asset bytes are not folder-scoped.
    func moveDocument(_ document: StoredDocument) async throws

    /// Enumerates all folders with a non-nil `deletedAt`.
    func trashedFolders() async throws -> [Folder]
    /// Enumerates all documents with a non-nil `deletedAt`.
    func trashedDocuments() async throws -> [StoredDocument]
    /// Permanently removes the folder and all its child documents/assets.
    func deleteFolder(id: UUID) async throws
    /// Returns true if any document other than `excludingDocumentId` references this asset.
    func hasOtherReferences(to asset: AssetReference, excludingDocumentId: UUID) async throws -> Bool

    func tags() async throws -> [Tag]
    func saveTag(_ tag: Tag) async throws

    func watermarkPresets() async throws -> [WatermarkPreset]
    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws
}

/// Read-only local archive search boundary. Feature UI receives typed value
/// results and never enumerates encrypted records or reads OCR text itself.
public protocol DocumentSearching: Sendable {
    func search(_ query: DocumentSearchQuery) async throws -> [ArchiveSearchResult]
}

/// Narrow preset-only persistence boundary. Watermark editing must not depend
/// on the document, tag, or asset repository surface.
public protocol WatermarkPresetStore: Sendable {
    func watermarkPresets() async throws -> [WatermarkPreset]
    func saveWatermarkPreset(_ preset: WatermarkPreset) async throws
}

/// Metadata boundary for recipient-based derived copies. Issuances are the
/// visibility/transaction unit; individual renditions remain addressable for
/// Trash and sharing.
public protocol WatermarkCopyRepository: Sendable {
    func watermarkRecipients() async throws -> [WatermarkRecipient]
    func saveWatermarkRecipient(_ recipient: WatermarkRecipient) async throws
    func watermarkIssuances() async throws -> [WatermarkIssuance]
    func saveWatermarkIssuance(_ issuance: WatermarkIssuance) async throws
    /// Atomically allocates recipient-relative versions and publishes the
    /// issuance. The returned value contains the committed version numbers.
    func commitWatermarkIssuance(
        _ issuance: WatermarkIssuance,
        recipient: WatermarkRecipient
    ) async throws -> WatermarkIssuance
    func removeWatermarkIssuance(id: UUID) async throws
}

public enum WatermarkCopyStoreError: Error, Equatable, Sendable {
    case duplicateRecipientName
    case unavailable
}

/// Privacy-safe failures for the narrow watermark preset persistence boundary.
/// Duplicate names deliberately carry no user-entered text.
public enum WatermarkPresetStoreError: Error, Equatable, Sendable {
    case unavailable
    case duplicateName
}

public protocol DocumentAssetStore: Sendable {
    func saveAsset(_ data: Data, reference: AssetReference) async throws
    func readAsset(_ reference: AssetReference) async throws -> Data
    func containsAsset(_ reference: AssetReference) async throws -> Bool
    func removeAsset(_ reference: AssetReference) async throws
}

public protocol DocumentScanning: Sendable {
    func scanDocument(into folderId: UUID, named name: String) async throws -> StoredDocument
}

/// Narrow read-only port for reopening a saved document and its page assets.
/// Deliberately excludes folders, tags, presets, and writes so a viewer-only
/// feature never depends on the full `DocumentRepository`/`DocumentAssetStore`
/// surface.
public protocol DocumentPageAssetLoading: Sendable {
    func document(id: UUID) async throws -> StoredDocument?
    func readAsset(_ reference: AssetReference) async throws -> Data
}

/// Narrow read-only port for a page's low-cost preview thumbnail, distinct
/// from `DocumentPageAssetLoading.readAsset` which returns the full-resolution
/// asset. Implementations own caching/generation/fallback so callers (e.g. a
/// document viewer's page rail) never decode a full-size page image just to
/// render a small preview.
public protocol DocumentPageThumbnailLoading: Sendable {
    func thumbnail(for page: DocumentPage) async throws -> Data
}

/// Private, on-device text recognition boundary. Implementations own image
/// decoding and platform framework objects; callers exchange only value types.
public protocol OCRRecognizing: Sendable {
    func recognize(imageData: Data, configuration: OCRConfiguration) async throws -> OCRRecognitionResult
}

public struct OCRConfiguration: Equatable, Sendable {
    public let preferredLanguages: [String]

    public init(preferredLanguages: [String] = []) {
        self.preferredLanguages = preferredLanguages
    }
}

/// Complete OCR output for one page. An empty `text` and `blocks` pair is a
/// valid no-text result, not a processing failure.
public struct OCRRecognitionResult: Equatable, Sendable {
    public let text: String
    public let blocks: [OCRBlock]

    public init(text: String, blocks: [OCRBlock]) {
        self.text = text.normalizedLineEndings()
        self.blocks = blocks
    }

    public var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func validate() throws {
        if hasText {
            guard !blocks.isEmpty else { throw DomainValidationError.emptyOCRText }
        } else {
            guard blocks.isEmpty else { throw DomainValidationError.emptyOCRText }
        }
        try blocks.forEach { try $0.validate() }
    }
}

/// Narrow read/write boundary for OCR. Keeps feature code independent from a
/// storage implementation while allowing one validated document update after
/// every page has completed recognition.
public protocol DocumentOCRPersisting: Sendable {
    func document(id: UUID) async throws -> StoredDocument?
    func readAsset(_ reference: AssetReference) async throws -> Data
    func saveDocument(_ document: StoredDocument) async throws
}

/// Privacy-safe OCR failures. Never include recognized text, asset paths, or
/// framework error payloads.
public enum OCRRecognitionError: Error, Equatable, Sendable {
    case imageUnreadable
    case requestFailed
    case invalidResult
}

/// Renders a document's immutable source pages plus one supported text
/// watermark layer (`WatermarkConfig.body`) into a transient PDF. Never
/// mutates, replaces, or deletes any source asset.
public protocol WatermarkPDFRendering: Sendable {
    func renderPDF(for document: StoredDocument, watermark config: WatermarkConfig) async throws -> Data
}

/// Privacy-safe, typed failures. Never carry document names, watermark text,
/// file paths, or raw framework error payloads.
public enum WatermarkRenderError: Error, Equatable, Sendable {
    /// `StoredDocument` failed contract validation (e.g. non-contiguous page
    /// indexes). Kept distinct from `invalidWatermarkConfig` so diagnostics
    /// stay accurate without exposing document content.
    case invalidDocument
    /// `WatermarkConfig` failed contract validation (e.g. malformed color hex).
    case invalidWatermarkConfig
    /// An enabled layer other than `body` was requested. The basic renderer
    /// must fail loudly instead of silently dropping requested content.
    case unsupportedWatermarkLayer(UnsupportedWatermarkLayer)
    /// A `layoutMode` other than `.single` was requested. The basic renderer
    /// does not implement tiled PDF output yet.
    case unsupportedLayoutMode(WatermarkLayoutMode)
    /// The page's `source` asset could not be read from the asset store.
    case sourceAssetUnreadable(pageIndex: Int)
    /// The page's `source` asset data could not be decoded as an image.
    case sourceImageUndecodable(pageIndex: Int)
    /// The page's `source` asset decoded to a zero-size image.
    case sourceImageEmpty(pageIndex: Int)
    /// An enabled watermark image could not be loaded from the asset store.
    case watermarkImageAssetUnreadable
    /// The stored watermark image bytes could not be decoded.
    case watermarkImageUndecodable
    /// Core Graphics failed to open or write the PDF context.
    case pdfGenerationFailed
}

public enum UnsupportedWatermarkLayer: Equatable, Sendable {
    case heading
    case caption
    case image
}

/// Port for detecting candidate document quadrilaterals and rectifying document photos
/// with perspective correction and non-destructive 90° rotations.
public protocol DocumentRectifying: Sendable {
    func detect(in jpegData: Data) async -> RectificationResult
    func detect(in jpegData: Data, strategy: DetectionStrategy) async -> RectificationResult
    func rectify(jpegData: Data, quadrilateral: CropQuadrilateral, rotationDegrees: Int) async -> Data?
}

extension DocumentRectifying {
    /// Conformers that only implement the balanced pass still satisfy the port;
    /// an aggressive request degrades to the balanced result rather than failing.
    public func detect(in jpegData: Data, strategy: DetectionStrategy) async -> RectificationResult {
        await detect(in: jpegData)
    }
}

/// Port for saving reviewed pages into a target folder.
public protocol CaptureSaving: Sendable {
    func save(pages: [ImportedPage], grouping: GalleryGrouping, folderID: UUID, name: String) async throws -> [StoredDocument]
}

/// Port for retrieving active folders and creating new folders during save.
public protocol CaptureFolderProviding: Sendable {
    func activeFolders() async -> [Folder]
    func mostRecentlyUsedFolderID() async -> UUID?
    func createFolder(name: String) async throws -> Folder
}
