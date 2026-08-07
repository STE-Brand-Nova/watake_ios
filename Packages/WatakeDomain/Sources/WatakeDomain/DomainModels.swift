import Foundation

public enum DomainValidationError: Error, Equatable, Sendable {
    case emptyName(field: String)
    case nameTooLong(field: String, maxLength: Int)
    case invalidColorHex(String)
    case invalidUUIDString(String)
    case invalidDateString(String)
    case documentRequiresPage
    case negativeOrderIndex(Int)
    case pageIndexesNotContiguous
    case duplicateTagIDs
    case invalidAssetPath(String)
    case invalidSHA256(String)
    case invalidByteSize(Int)
    case ocrBoundsOutsideUnitSquare
    case emptyOCRText
    case ocrConfidenceOutOfRange(Double)
    case invalidOCRLanguageTag(String)
    case opacityOutOfRange(Double)
    case rotationOutOfRange(Double)
    case imageScaleOutOfRange(Double)
    case invalidSchemaVersion(Int)
    case duplicateExportDraftPageIDs
    case tileSpacingRequiredForTiledLayout
    case tileSpacingMustBeNilForSingleLayout
    case tileSpacingOutOfRange(Double)
}

public enum WatakeContractCoding {
    public static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatUTCDate(date))
        }
        return encoder
    }

    public static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseUTCDate(string) else {
                throw DomainValidationError.invalidDateString(string)
            }
            return date
        }
        return decoder
    }

    private static func formatUTCDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func parseUTCDate(_ value: String) -> Date? {
        guard value.hasSuffix("Z") else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)
    }
}

public struct Folder: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let createdAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        createdAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    public func validate() throws {
        try DomainValidation.validateTrimmed(name, field: "name", maxLength: 120)
        try DomainValidation.validateColorHex(colorHex)
    }
}

public struct StoredDocument: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let folderId: UUID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let orderIndex: Int
    public let pages: [DocumentPage]
    public let deletedAt: Date?
    public let tagIds: [UUID]
    public let watermarkPresetId: UUID?

    public init(
        id: UUID,
        folderId: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        orderIndex: Int,
        pages: [DocumentPage],
        deletedAt: Date? = nil,
        tagIds: [UUID] = [],
        watermarkPresetId: UUID? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.orderIndex = orderIndex
        self.pages = pages
        self.deletedAt = deletedAt
        self.tagIds = tagIds
        self.watermarkPresetId = watermarkPresetId
    }

    public func validate() throws {
        try DomainValidation.validateTrimmed(name, field: "name", maxLength: 200)
        try DomainValidation.validateOrderIndex(orderIndex)
        try DomainValidation.validateDocumentPages(pages)
        try DomainValidation.validateUniqueTagIDs(tagIds)
        try pages.forEach { try $0.validate() }
    }

    public var hasOCRText: Bool {
        pages.contains { page in
            guard let text = page.ocrText else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct DocumentPage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let index: Int
    public let source: AssetReference
    public let rectified: AssetReference?
    public let ocrText: String?
    public let ocrBlocks: [OCRBlock]

    public init(
        id: UUID,
        index: Int,
        source: AssetReference,
        rectified: AssetReference? = nil,
        ocrText: String? = nil,
        ocrBlocks: [OCRBlock] = []
    ) {
        self.id = id
        self.index = index
        self.source = source
        self.rectified = rectified
        self.ocrText = ocrText?.normalizedLineEndings()
        self.ocrBlocks = ocrBlocks
    }

    public func validate() throws {
        try source.validate()
        try rectified?.validate()
        try ocrBlocks.forEach { try $0.validate() }
    }
}

public struct AssetReference: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let relativePath: String
    public let sha256Hex: String
    public let byteSize: Int
    public let mediaType: String?

    public init(id: UUID, relativePath: String, sha256Hex: String, byteSize: Int, mediaType: String? = nil) {
        self.id = id
        self.relativePath = relativePath
        self.sha256Hex = sha256Hex
        self.byteSize = byteSize
        self.mediaType = mediaType
    }

    public func validate() throws {
        try DomainValidation.validateAssetPath(relativePath)
        try DomainValidation.validateSHA256(sha256Hex)
        try DomainValidation.validateByteSize(byteSize)
    }
}

public struct NormalizedRect: Codable, Equatable, Sendable {
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double

    public init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    public func validateForOCR() throws {
        guard isInsideUnitSquare else {
            throw DomainValidationError.ocrBoundsOutsideUnitSquare
        }
    }

    private var isInsideUnitSquare: Bool {
        originX.isFinite &&
            originY.isFinite &&
            width.isFinite &&
            height.isFinite &&
            originX >= 0 &&
            originY >= 0 &&
            width >= 0 &&
            height >= 0 &&
            originX + width <= 1 &&
            originY + height <= 1
    }
}

public struct OCRBlock: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let confidence: Double
    public let bounds: NormalizedRect
    public let language: String?

    public init(
        id: UUID,
        text: String,
        confidence: Double = 1,
        bounds: NormalizedRect,
        language: String? = nil
    ) {
        self.id = id
        self.text = text.normalizedLineEndings()
        self.confidence = confidence
        self.bounds = bounds
        self.language = language
    }

    public func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyOCRText
        }
        guard confidence.isFinite, (0 ... 1).contains(confidence) else {
            throw DomainValidationError.ocrConfidenceOutOfRange(confidence)
        }
        if let language {
            try DomainValidation.validateBCP47LanguageTag(language)
        }
        try bounds.validateForOCR()
    }
}

public struct Tag: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let colorHex: String

    public init(id: UUID, label: String, colorHex: String) {
        self.id = id
        self.label = label
        self.colorHex = colorHex
    }

    public func validate() throws {
        try DomainValidation.validateTrimmed(label, field: "label", maxLength: 50)
        try DomainValidation.validateColorHex(colorHex)
    }
}

public struct WatermarkConfig: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let automatic: Bool
    public let heading: WatermarkTextLayer?
    public let body: WatermarkTextLayer?
    public let caption: WatermarkTextLayer?
    public let image: WatermarkImageLayer?
    public let globalPosition: WatermarkPosition
    public let globalRotation: Double
    public let globalOpacity: Double
    public let layoutMode: WatermarkLayoutMode
    public let tileSpacingX: Double?
    public let tileSpacingY: Double?

    public init(
        schemaVersion: Int = 1,
        automatic: Bool,
        heading: WatermarkTextLayer? = nil,
        body: WatermarkTextLayer? = nil,
        caption: WatermarkTextLayer? = nil,
        image: WatermarkImageLayer? = nil,
        globalPosition: WatermarkPosition,
        globalRotation: Double,
        globalOpacity: Double,
        layoutMode: WatermarkLayoutMode = .single,
        tileSpacingX: Double? = nil,
        tileSpacingY: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.automatic = automatic
        self.heading = heading
        self.body = body
        self.caption = caption
        self.image = image
        self.globalPosition = globalPosition
        self.globalRotation = globalRotation
        self.globalOpacity = globalOpacity
        self.layoutMode = layoutMode
        self.tileSpacingX = tileSpacingX
        self.tileSpacingY = tileSpacingY
    }

    public func validate() throws {
        try DomainValidation.validateSchemaVersion(schemaVersion)
        try DomainValidation.validateRotation(globalRotation)
        try DomainValidation.validateOpacity(globalOpacity)
        try DomainValidation.validateTileSpacing(layoutMode: layoutMode, tileSpacingX: tileSpacingX, tileSpacingY: tileSpacingY)
        try heading?.validate()
        try body?.validate()
        try caption?.validate()
        try image?.validate()
    }
}

public struct WatermarkTextLayer: Codable, Equatable, Sendable {
    public let text: String
    public let enabled: Bool
    public let fontName: String
    public let sizePreset: WatermarkSizePreset
    public let colorHex: String
    public let rotation: Double
    public let opacity: Double

    public init(
        text: String,
        enabled: Bool,
        fontName: String,
        sizePreset: WatermarkSizePreset,
        colorHex: String,
        rotation: Double,
        opacity: Double
    ) {
        self.text = text
        self.enabled = enabled
        self.fontName = fontName
        self.sizePreset = sizePreset
        self.colorHex = colorHex
        self.rotation = rotation
        self.opacity = opacity
    }

    public func validate() throws {
        try DomainValidation.validateColorHex(colorHex)
        try DomainValidation.validateRotation(rotation)
        try DomainValidation.validateOpacity(opacity)
    }

    /// A text layer participates in a composition only when the person has
    /// enabled it and it contains visible text. Keeping this at the domain
    /// boundary gives previews and eventual export renderers the same safe
    /// eligibility rule.
    public var isRenderable: Bool {
        enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension WatermarkConfig {
    /// Text layers in the contract's required visual composition order.
    /// Disabled or empty layers are intentionally omitted so consumers never
    /// need to duplicate the eligibility rule before rendering.
    public var renderableTextLayersInCompositionOrder: [WatermarkTextLayer] {
        [heading, body, caption]
            .compactMap(\.self)
            .filter(\.isRenderable)
    }
}

public struct WatermarkImageLayer: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let assetRef: AssetReference
    public let scale: Double
    public let tintHex: String?
    public let rotation: Double
    public let opacity: Double
    public let placement: WatermarkImagePlacement

    public init(
        enabled: Bool,
        assetRef: AssetReference,
        scale: Double,
        tintHex: String? = nil,
        rotation: Double,
        opacity: Double,
        placement: WatermarkImagePlacement
    ) {
        self.enabled = enabled
        self.assetRef = assetRef
        self.scale = scale
        self.tintHex = tintHex
        self.rotation = rotation
        self.opacity = opacity
        self.placement = placement
    }

    public func validate() throws {
        try assetRef.validate()
        try tintHex.map(DomainValidation.validateColorHex)
        try DomainValidation.validateRotation(rotation)
        try DomainValidation.validateOpacity(opacity)
        guard scale >= 0.1, scale <= 3 else {
            throw DomainValidationError.imageScaleOutOfRange(scale)
        }
    }
}

public enum WatermarkSizePreset: String, Codable, Equatable, Sendable {
    case small
    case medium
    case large
}

public enum WatermarkPosition: String, Codable, Equatable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case midLeft
    case center
    case midRight
    case botLeft
    case botCenter
    case botRight
}

public enum WatermarkImagePlacement: String, Codable, Equatable, Sendable {
    case behindText
    case aboveText
    case leftOfText
    case rightOfText
}

/// Whether a watermark composite renders once or repeats across the page in
/// a deterministic grid. See `WatermarkTileLayoutCalculator` for the tiled
/// grid math.
public enum WatermarkLayoutMode: String, Codable, Equatable, Sendable {
    case single
    case tiled
}

public struct WatermarkPreset: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let config: WatermarkConfig
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, name: String, config: WatermarkConfig, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.config = config
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        try DomainValidation.validateTrimmed(name, field: "name", maxLength: 120)
        try config.validate()
    }
}

public struct WatermarkRendition: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let documentId: UUID
    public let config: WatermarkConfig
    public let pages: [RenditionPage]
    public let createdAt: Date

    public init(id: UUID, documentId: UUID, config: WatermarkConfig, pages: [RenditionPage], createdAt: Date) {
        self.id = id
        self.documentId = documentId
        self.config = config
        self.pages = pages
        self.createdAt = createdAt
    }

    public func validate() throws {
        try config.validate()
        try DomainValidation.validateRenditionPages(pages)
        try pages.forEach { try $0.validate() }
    }
}

public struct RenditionPage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let pageId: UUID
    public let index: Int
    public let watermarked: AssetReference

    public init(id: UUID, pageId: UUID, index: Int, watermarked: AssetReference) {
        self.id = id
        self.pageId = pageId
        self.index = index
        self.watermarked = watermarked
    }

    public func validate() throws {
        try watermarked.validate()
    }
}

public struct ExportDraft: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let documentId: UUID
    public let pageIds: [UUID]
    public let format: ExportFormat
    public let createdAt: Date

    public init(id: UUID, documentId: UUID, pageIds: [UUID], format: ExportFormat, createdAt: Date) {
        self.id = id
        self.documentId = documentId
        self.pageIds = pageIds
        self.format = format
        self.createdAt = createdAt
    }

    public func validate() throws {
        guard Set(pageIds).count == pageIds.count else {
            throw DomainValidationError.duplicateExportDraftPageIDs
        }
    }
}

public enum ExportFormat: String, Codable, Equatable, Sendable {
    case pdf
    case pptx
}
