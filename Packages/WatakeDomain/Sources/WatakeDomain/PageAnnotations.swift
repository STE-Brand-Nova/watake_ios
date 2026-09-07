import Foundation

public enum PageAnnotationKind: String, Codable, CaseIterable, Sendable {
    case text
    case signature
    case image
    case highlight
}

public enum AnnotationTextAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

/// Page-relative geometry. Normalized coordinates make annotations retain
/// visual placement when preview and output resolutions differ.
public struct AnnotationTransform: Codable, Equatable, Sendable {
    public let centerX: Double
    public let centerY: Double
    public let width: Double
    public let height: Double
    public let rotation: Double

    public init(centerX: Double, centerY: Double, width: Double, height: Double, rotation: Double = 0) {
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
        self.rotation = rotation
    }

    public func validate() throws {
        guard centerX.isFinite, centerY.isFinite, width.isFinite, height.isFinite,
              (0 ... 1).contains(centerX), (0 ... 1).contains(centerY),
              width >= 0.01, width <= 1, height >= 0.01, height <= 1 else {
            throw DomainValidationError.annotationGeometryInvalid
        }
        try DomainValidation.validateRotation(rotation)
    }
}

public struct AnnotationText: Codable, Equatable, Sendable {
    public let text: String
    public let fontName: String
    /// Font height relative to page's shorter edge.
    public let fontSize: Double
    public let colorHex: String
    public let alignment: AnnotationTextAlignment
    public let isBold: Bool
    public let isItalic: Bool
    public let isUnderlined: Bool

    public init(
        text: String,
        fontName: String = "Helvetica",
        fontSize: Double = 0.04,
        colorHex: String = "#0B1220",
        alignment: AnnotationTextAlignment = .leading,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false
    ) {
        self.text = text.normalizedLineEndings()
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.alignment = alignment
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
    }

    public func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 5000,
              !fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fontName.count <= 120,
              fontSize.isFinite, fontSize >= 0.01, fontSize <= 0.25 else {
            throw DomainValidationError.annotationPayloadInvalid
        }
        try DomainValidation.validateColorHex(colorHex)
    }
}

public struct InkPoint: Codable, Equatable, Sendable {
    public let location: NormalizedPoint
    public let pressure: Double

    public init(location: NormalizedPoint, pressure: Double = 1) {
        self.location = location
        self.pressure = pressure
    }

    public func validate() throws {
        guard location.x.isFinite, location.y.isFinite,
              (0 ... 1).contains(location.x), (0 ... 1).contains(location.y),
              pressure.isFinite, (0 ... 1).contains(pressure) else {
            throw DomainValidationError.annotationPayloadInvalid
        }
    }
}

public struct InkStroke: Codable, Equatable, Sendable {
    public let points: [InkPoint]
    /// Width relative to page's shorter edge.
    public let width: Double
    public let colorHex: String
    public let opacity: Double

    public init(points: [InkPoint], width: Double, colorHex: String, opacity: Double = 1) {
        self.points = points
        self.width = width
        self.colorHex = colorHex
        self.opacity = opacity
    }

    public func validate() throws {
        guard points.count >= 2, points.count <= 20000,
              width.isFinite, width >= 0.001, width <= 0.2 else {
            throw DomainValidationError.annotationPayloadInvalid
        }
        try points.forEach { try $0.validate() }
        try DomainValidation.validateColorHex(colorHex)
        try DomainValidation.validateOpacity(opacity)
    }
}

/// One editable page layer. Kind-specific payloads remain explicit so JSON
/// never relies on framework-owned types.
public struct PageAnnotation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: PageAnnotationKind
    public let transform: AnnotationTransform
    public let opacity: Double
    public let zIndex: Int
    public let text: AnnotationText?
    public let strokes: [InkStroke]
    public let image: AssetReference?
    public let isStraightened: Bool

    public init(
        id: UUID,
        kind: PageAnnotationKind,
        transform: AnnotationTransform,
        opacity: Double = 1,
        zIndex: Int,
        text: AnnotationText? = nil,
        strokes: [InkStroke] = [],
        image: AssetReference? = nil,
        isStraightened: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.transform = transform
        self.opacity = opacity
        self.zIndex = zIndex
        self.text = text
        self.strokes = strokes
        self.image = image
        self.isStraightened = isStraightened
    }

    public func validate() throws {
        try transform.validate()
        try DomainValidation.validateOpacity(opacity)
        guard zIndex >= 0 else { throw DomainValidationError.annotationZIndexInvalid }
        switch kind {
        case .text:
            guard let text, strokes.isEmpty, image == nil else { throw DomainValidationError.annotationPayloadInvalid }
            try text.validate()
        case .signature:
            guard text == nil, !strokes.isEmpty, image == nil else { throw DomainValidationError.annotationPayloadInvalid }
            try strokes.forEach { try $0.validate() }
        case .image:
            guard text == nil, strokes.isEmpty, let image else { throw DomainValidationError.annotationPayloadInvalid }
            try image.validate()
        case .highlight:
            guard text == nil, !strokes.isEmpty, image == nil else { throw DomainValidationError.annotationPayloadInvalid }
            try strokes.forEach { try $0.validate() }
        }
    }
}

public struct SavedSignature: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let strokes: [InkStroke]
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, name: String, strokes: [InkStroke], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.strokes = strokes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        try DomainValidation.validateTrimmed(name, field: "signature.name", maxLength: 80)
        guard !strokes.isEmpty else { throw DomainValidationError.annotationPayloadInvalid }
        try strokes.forEach { try $0.validate() }
        guard updatedAt >= createdAt else { throw DomainValidationError.annotationPayloadInvalid }
    }
}

public struct DocumentEditRecoveryDraft: Codable, Equatable, Sendable {
    public let document: StoredDocument
    public let sourceDocumentID: UUID
    public let selectedPageID: UUID
    public let stagedAssets: [AssetReference]
    public let savedAt: Date

    public init(
        document: StoredDocument,
        sourceDocumentID: UUID,
        selectedPageID: UUID,
        stagedAssets: [AssetReference],
        savedAt: Date
    ) {
        self.document = document
        self.sourceDocumentID = sourceDocumentID
        self.selectedPageID = selectedPageID
        self.stagedAssets = stagedAssets
        self.savedAt = savedAt
    }

    public func validate() throws {
        try document.validate()
        guard document.pages.contains(where: { $0.id == selectedPageID }) else {
            throw DomainValidationError.annotationPayloadInvalid
        }
        try stagedAssets.forEach { try $0.validate() }
    }
}
