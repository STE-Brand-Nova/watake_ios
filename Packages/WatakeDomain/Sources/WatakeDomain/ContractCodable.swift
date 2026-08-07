import Foundation

extension Folder {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case createdAt
        case deletedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            name: container.decode(String.self, forKey: .name),
            colorHex: container.decode(String.self, forKey: .colorHex),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            deletedAt: container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

extension StoredDocument {
    enum CodingKeys: String, CodingKey {
        case id
        case folderId
        case name
        case createdAt
        case updatedAt
        case orderIndex
        case pages
        case deletedAt
        case tagIds
        case watermarkPresetId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            folderId: container.decodeLowercaseUUID(forKey: .folderId),
            name: container.decode(String.self, forKey: .name),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt),
            orderIndex: container.decode(Int.self, forKey: .orderIndex),
            pages: container.decode([DocumentPage].self, forKey: .pages),
            deletedAt: container.decodeIfPresent(Date.self, forKey: .deletedAt),
            tagIds: container.decodeLowercaseUUIDs(forKey: .tagIds),
            watermarkPresetId: container.decodeLowercaseUUIDIfPresent(forKey: .watermarkPresetId)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encodeLowercaseUUID(folderId, forKey: .folderId)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(pages, forKey: .pages)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeLowercaseUUIDs(tagIds, forKey: .tagIds)
        try container.encodeLowercaseUUIDIfPresent(watermarkPresetId, forKey: .watermarkPresetId)
    }
}

extension DocumentPage {
    enum CodingKeys: String, CodingKey {
        case id
        case index
        case source
        case rectified
        case ocrText
        case ocrBlocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            index: container.decode(Int.self, forKey: .index),
            source: container.decode(AssetReference.self, forKey: .source),
            rectified: container.decodeIfPresent(AssetReference.self, forKey: .rectified),
            ocrText: container.decodeIfPresent(String.self, forKey: .ocrText),
            ocrBlocks: container.decode([OCRBlock].self, forKey: .ocrBlocks)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encode(index, forKey: .index)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(rectified, forKey: .rectified)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
        try container.encode(ocrBlocks, forKey: .ocrBlocks)
    }
}

extension AssetReference {
    enum CodingKeys: String, CodingKey {
        case id
        case relativePath
        case sha256Hex
        case byteSize
        case mediaType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            relativePath: container.decode(String.self, forKey: .relativePath),
            sha256Hex: container.decode(String.self, forKey: .sha256Hex),
            byteSize: container.decode(Int.self, forKey: .byteSize),
            mediaType: container.decodeIfPresent(String.self, forKey: .mediaType)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(sha256Hex, forKey: .sha256Hex)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encodeIfPresent(mediaType, forKey: .mediaType)
    }
}

extension OCRBlock {
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case confidence
        case bounds
        case language
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            text: container.decode(String.self, forKey: .text),
            confidence: container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1,
            bounds: container.decode(NormalizedRect.self, forKey: .bounds),
            language: container.decodeIfPresent(String.self, forKey: .language)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(bounds, forKey: .bounds)
        try container.encodeIfPresent(language, forKey: .language)
    }
}

extension NormalizedRect {
    enum CodingKeys: String, CodingKey {
        case originX
        case originY
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            originX: container.decode(Double.self, forKey: .originX),
            originY: container.decode(Double.self, forKey: .originY),
            width: container.decode(Double.self, forKey: .width),
            height: container.decode(Double.self, forKey: .height)
        )
        try validateForOCR()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originX, forKey: .originX)
        try container.encode(originY, forKey: .originY)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
}

extension Tag {
    enum CodingKeys: String, CodingKey {
        case id
        case label
        case colorHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            label: container.decode(String.self, forKey: .label),
            colorHex: container.decode(String.self, forKey: .colorHex)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(colorHex, forKey: .colorHex)
    }
}

extension WatermarkConfig {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case automatic
        case heading
        case body
        case caption
        case image
        case globalPosition
        case globalRotation
        case globalOpacity
        case layoutMode
        case tileSpacingX
        case tileSpacingY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            automatic: container.decode(Bool.self, forKey: .automatic),
            heading: container.decodeIfPresent(WatermarkTextLayer.self, forKey: .heading),
            body: container.decodeIfPresent(WatermarkTextLayer.self, forKey: .body),
            caption: container.decodeIfPresent(WatermarkTextLayer.self, forKey: .caption),
            image: container.decodeIfPresent(WatermarkImageLayer.self, forKey: .image),
            globalPosition: container.decode(WatermarkPosition.self, forKey: .globalPosition),
            globalRotation: container.decode(Double.self, forKey: .globalRotation),
            globalOpacity: container.decode(Double.self, forKey: .globalOpacity),
            // Omitted in configs serialized before this v1 field addition;
            // those decode as `.single` with nil spacing.
            layoutMode: container.decodeIfPresent(WatermarkLayoutMode.self, forKey: .layoutMode) ?? .single,
            tileSpacingX: container.decodeIfPresent(Double.self, forKey: .tileSpacingX),
            tileSpacingY: container.decodeIfPresent(Double.self, forKey: .tileSpacingY)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(automatic, forKey: .automatic)
        try container.encodeIfPresent(heading, forKey: .heading)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(globalPosition, forKey: .globalPosition)
        try container.encode(globalRotation, forKey: .globalRotation)
        try container.encode(globalOpacity, forKey: .globalOpacity)
        // The bundle contract requires writers to emit the oldest format that
        // represents the data: `.single` is the pre-tiling default, so it
        // round-trips through legacy readers unchanged only if these three
        // fields are omitted entirely rather than written as "single"/null.
        if layoutMode != .single {
            try container.encode(layoutMode, forKey: .layoutMode)
            try container.encodeIfPresent(tileSpacingX, forKey: .tileSpacingX)
            try container.encodeIfPresent(tileSpacingY, forKey: .tileSpacingY)
        }
    }
}

extension WatermarkTextLayer {
    enum CodingKeys: String, CodingKey {
        case text
        case enabled
        case fontName
        case sizePreset
        case colorHex
        case rotation
        case opacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            text: container.decode(String.self, forKey: .text),
            enabled: container.decode(Bool.self, forKey: .enabled),
            fontName: container.decode(String.self, forKey: .fontName),
            sizePreset: container.decode(WatermarkSizePreset.self, forKey: .sizePreset),
            colorHex: container.decode(String.self, forKey: .colorHex),
            rotation: container.decode(Double.self, forKey: .rotation),
            opacity: container.decode(Double.self, forKey: .opacity)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(sizePreset, forKey: .sizePreset)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(opacity, forKey: .opacity)
    }
}

extension WatermarkImageLayer {
    enum CodingKeys: String, CodingKey {
        case enabled
        case assetRef
        case scale
        case tintHex
        case rotation
        case opacity
        case placement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            enabled: container.decode(Bool.self, forKey: .enabled),
            assetRef: container.decode(AssetReference.self, forKey: .assetRef),
            scale: container.decode(Double.self, forKey: .scale),
            tintHex: container.decodeIfPresent(String.self, forKey: .tintHex),
            rotation: container.decode(Double.self, forKey: .rotation),
            opacity: container.decode(Double.self, forKey: .opacity),
            placement: container.decode(WatermarkImagePlacement.self, forKey: .placement)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(assetRef, forKey: .assetRef)
        try container.encode(scale, forKey: .scale)
        try container.encodeIfPresent(tintHex, forKey: .tintHex)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(placement, forKey: .placement)
    }
}

extension WatermarkPreset {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case config
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            name: container.decode(String.self, forKey: .name),
            config: container.decode(WatermarkConfig.self, forKey: .config),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(config, forKey: .config)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension WatermarkRendition {
    enum CodingKeys: String, CodingKey {
        case id
        case documentId
        case config
        case pages
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            documentId: container.decodeLowercaseUUID(forKey: .documentId),
            config: container.decode(WatermarkConfig.self, forKey: .config),
            pages: container.decode([RenditionPage].self, forKey: .pages),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encodeLowercaseUUID(documentId, forKey: .documentId)
        try container.encode(config, forKey: .config)
        try container.encode(pages, forKey: .pages)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension RenditionPage {
    enum CodingKeys: String, CodingKey {
        case id
        case pageId
        case index
        case watermarked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            pageId: container.decodeLowercaseUUID(forKey: .pageId),
            index: container.decode(Int.self, forKey: .index),
            watermarked: container.decode(AssetReference.self, forKey: .watermarked)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encodeLowercaseUUID(pageId, forKey: .pageId)
        try container.encode(index, forKey: .index)
        try container.encode(watermarked, forKey: .watermarked)
    }
}

extension ExportDraft {
    enum CodingKeys: String, CodingKey {
        case id
        case documentId
        case pageIds
        case format
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeLowercaseUUID(forKey: .id),
            documentId: container.decodeLowercaseUUID(forKey: .documentId),
            pageIds: container.decodeLowercaseUUIDs(forKey: .pageIds),
            format: container.decode(ExportFormat.self, forKey: .format),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeLowercaseUUID(id, forKey: .id)
        try container.encodeLowercaseUUID(documentId, forKey: .documentId)
        try container.encodeLowercaseUUIDs(pageIds, forKey: .pageIds)
        try container.encode(format, forKey: .format)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension KeyedDecodingContainer {
    fileprivate func decodeLowercaseUUID(forKey key: Key) throws -> UUID {
        let string = try decode(String.self, forKey: key)
        return try DomainValidation.validateUUIDString(string)
    }

    fileprivate func decodeLowercaseUUIDIfPresent(forKey key: Key) throws -> UUID? {
        guard let string = try decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return try DomainValidation.validateUUIDString(string)
    }

    fileprivate func decodeLowercaseUUIDs(forKey key: Key) throws -> [UUID] {
        let strings = try decode([String].self, forKey: key)
        return try strings.map(DomainValidation.validateUUIDString)
    }
}

extension KeyedEncodingContainer {
    fileprivate mutating func encodeLowercaseUUID(_ value: UUID, forKey key: Key) throws {
        try encode(value.uuidString.lowercased(), forKey: key)
    }

    fileprivate mutating func encodeLowercaseUUIDIfPresent(_ value: UUID?, forKey key: Key) throws {
        guard let value else {
            return
        }
        try encodeLowercaseUUID(value, forKey: key)
    }

    fileprivate mutating func encodeLowercaseUUIDs(_ values: [UUID], forKey key: Key) throws {
        try encode(values.map { $0.uuidString.lowercased() }, forKey: key)
    }
}

extension String {
    func normalizedLineEndings() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
