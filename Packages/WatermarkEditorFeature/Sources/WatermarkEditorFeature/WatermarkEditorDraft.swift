import Foundation
import WatakeDomain

/// The editable watermark tabs. Global controls remain visibly unavailable
/// until their dedicated slice is implemented.
public enum WatermarkEditorTab: String, CaseIterable, Identifiable, Sendable {
    case heading
    case body
    case caption
    case image
    case global

    public var id: Self {
        self
    }

    public var title: String {
        rawValue.capitalized
    }
}

public enum WatermarkTextLayerKind: String, CaseIterable, Identifiable, Sendable {
    case heading
    case body
    case caption

    public var id: Self {
        self
    }

    public var title: String {
        rawValue.capitalized
    }
}

/// Editing-safe text-layer representation. Its coding keys exactly match the
/// shared `WatermarkTextLayer` contract, and initialization/decoding clamp
/// numeric values before a renderer can observe them.
public struct EditableWatermarkTextLayer: Codable, Equatable, Sendable {
    public private(set) var text: String
    public private(set) var enabled: Bool
    public private(set) var fontName: String
    public private(set) var sizePreset: WatermarkSizePreset
    public private(set) var colorHex: String
    public private(set) var rotation: Double
    public private(set) var opacity: Double

    public init(
        text: String = "",
        enabled: Bool = false,
        fontName: String = WatermarkFontCatalog.defaultFontName,
        sizePreset: WatermarkSizePreset = .medium,
        colorHex: String = WatermarkSemanticColor.ink.hex,
        rotation: Double = 0,
        opacity: Double = 1
    ) {
        self.text = text
        self.enabled = enabled
        self.fontName = WatermarkFontCatalog.sanitized(fontName)
        self.sizePreset = sizePreset
        self.colorHex = WatermarkHexColor.normalized(colorHex) ?? WatermarkSemanticColor.ink.hex
        self.rotation = Self.clampedRotation(rotation)
        self.opacity = Self.clampedOpacity(opacity)
    }

    public init(_ layer: WatermarkTextLayer) {
        self.init(
            text: layer.text,
            enabled: layer.enabled,
            fontName: layer.fontName,
            sizePreset: layer.sizePreset,
            colorHex: layer.colorHex,
            rotation: layer.rotation,
            opacity: layer.opacity
        )
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case enabled
        case fontName
        case sizePreset
        case colorHex
        case rotation
        case opacity
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            text: container.decodeIfPresent(String.self, forKey: .text) ?? "",
            enabled: container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            fontName: container.decodeIfPresent(String.self, forKey: .fontName) ?? WatermarkFontCatalog.defaultFontName,
            sizePreset: container.decodeIfPresent(WatermarkSizePreset.self, forKey: .sizePreset) ?? .medium,
            colorHex: container.decodeIfPresent(String.self, forKey: .colorHex) ?? WatermarkSemanticColor.ink.hex,
            rotation: container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0,
            opacity: container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        )
    }

    public var isRenderable: Bool {
        enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func watermarkTextLayer() -> WatermarkTextLayer {
        WatermarkTextLayer(
            text: text,
            enabled: enabled,
            fontName: fontName,
            sizePreset: sizePreset,
            colorHex: colorHex,
            rotation: rotation,
            opacity: opacity
        )
    }

    public mutating func setText(_ value: String) {
        text = value
    }

    public mutating func setEnabled(_ value: Bool) {
        enabled = value
    }

    public mutating func setFontName(_ value: String) {
        fontName = WatermarkFontCatalog.sanitized(value)
    }

    public mutating func setSizePreset(_ value: WatermarkSizePreset) {
        sizePreset = value
    }

    /// Rejects malformed input while preserving the last safe render color.
    /// UI code retains the raw input separately so a person can correct a
    /// partially typed hex value without ever crashing the preview.
    public mutating func setColorHex(_ value: String) {
        guard let normalized = WatermarkHexColor.normalized(value) else { return }
        colorHex = normalized
    }

    public mutating func setRotation(_ value: Double) {
        rotation = Self.clampedRotation(value)
    }

    public mutating func setOpacity(_ value: Double) {
        opacity = Self.clampedOpacity(value)
    }

    private static func clampedRotation(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -180), 180)
    }

    private static func clampedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }
}

/// In-memory working copy. It deliberately has no document identifier,
/// repository, or persistence operation: closing the editor discards it.
public struct WatermarkEditorDraft: Codable, Equatable, Sendable {
    /// Safe defaults supplied the moment a person switches to tiled layout.
    /// Chosen to produce a readable, non-crowded grid immediately.
    public static let defaultTileSpacingX = 0.35
    public static let defaultTileSpacingY = 0.28

    public private(set) var heading: EditableWatermarkTextLayer
    public private(set) var body: EditableWatermarkTextLayer
    public private(set) var caption: EditableWatermarkTextLayer
    public private(set) var image: EditableWatermarkImageLayer
    public private(set) var globalPosition: WatermarkPosition
    public private(set) var globalRotation: Double
    public private(set) var globalOpacity: Double
    public private(set) var layoutMode: WatermarkLayoutMode
    public private(set) var tileSpacingX: Double?
    public private(set) var tileSpacingY: Double?

    public init(
        heading: EditableWatermarkTextLayer = .init(),
        body: EditableWatermarkTextLayer = .init(),
        caption: EditableWatermarkTextLayer = .init(),
        image: EditableWatermarkImageLayer = .init(),
        globalPosition: WatermarkPosition = .center,
        globalRotation: Double = 0,
        globalOpacity: Double = 1,
        layoutMode: WatermarkLayoutMode = .single,
        tileSpacingX: Double? = nil,
        tileSpacingY: Double? = nil
    ) {
        self.heading = heading
        self.body = body
        self.caption = caption
        self.image = image
        self.globalPosition = globalPosition
        self.globalRotation = min(max(globalRotation.isFinite ? globalRotation : 0, -180), 180)
        self.globalOpacity = min(max(globalOpacity.isFinite ? globalOpacity : 1, 0), 1)
        self.layoutMode = layoutMode
        self.tileSpacingX = tileSpacingX
        self.tileSpacingY = tileSpacingY
    }

    public init(config: WatermarkConfig) {
        heading = config.heading.map(EditableWatermarkTextLayer.init) ?? .init()
        body = config.body.map(EditableWatermarkTextLayer.init) ?? .init()
        caption = config.caption.map(EditableWatermarkTextLayer.init) ?? .init()
        image = config.image.map {
            EditableWatermarkImageLayer(
                enabled: $0.enabled,
                assetReference: $0.assetRef,
                scale: $0.scale,
                tintHex: $0.tintHex,
                rotation: $0.rotation,
                opacity: $0.opacity,
                placement: $0.placement
            )
        } ?? .init()
        globalPosition = config.globalPosition
        globalRotation = config.globalRotation
        globalOpacity = config.globalOpacity
        layoutMode = config.layoutMode
        tileSpacingX = config.tileSpacingX
        tileSpacingY = config.tileSpacingY
    }

    private enum CodingKeys: String, CodingKey {
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heading = try container.decodeIfPresent(EditableWatermarkTextLayer.self, forKey: .heading) ?? .init()
        body = try container.decodeIfPresent(EditableWatermarkTextLayer.self, forKey: .body) ?? .init()
        caption = try container.decodeIfPresent(EditableWatermarkTextLayer.self, forKey: .caption) ?? .init()
        image = try container.decodeIfPresent(EditableWatermarkImageLayer.self, forKey: .image) ?? .init()
        globalPosition = try container.decodeIfPresent(WatermarkPosition.self, forKey: .globalPosition) ?? .center
        globalRotation = try container.decodeIfPresent(Double.self, forKey: .globalRotation) ?? 0
        globalOpacity = try container.decodeIfPresent(Double.self, forKey: .globalOpacity) ?? 1
        layoutMode = try container.decodeIfPresent(WatermarkLayoutMode.self, forKey: .layoutMode) ?? .single
        tileSpacingX = try container.decodeIfPresent(Double.self, forKey: .tileSpacingX)
        tileSpacingY = try container.decodeIfPresent(Double.self, forKey: .tileSpacingY)
    }

    /// Switching to tiled supplies safe defaults; switching to single clears
    /// both spacing values so the contract's "single implies nil spacing"
    /// invariant always holds for a value produced by the editor.
    public mutating func setLayoutMode(_ value: WatermarkLayoutMode) {
        layoutMode = value
        switch value {
        case .single:
            tileSpacingX = nil
            tileSpacingY = nil
        case .tiled:
            tileSpacingX = tileSpacingX ?? Self.defaultTileSpacingX
            tileSpacingY = tileSpacingY ?? Self.defaultTileSpacingY
        }
    }

    /// No-op outside tiled layout: spacing has no meaning for `.single`.
    public mutating func setTileSpacingX(_ value: Double) {
        guard layoutMode == .tiled else { return }
        tileSpacingX = Self.clampedSpacing(value, fallback: Self.defaultTileSpacingX)
    }

    public mutating func setTileSpacingY(_ value: Double) {
        guard layoutMode == .tiled else { return }
        tileSpacingY = Self.clampedSpacing(value, fallback: Self.defaultTileSpacingY)
    }

    private static func clampedSpacing(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, 0.10), 1.00)
    }

    public func layer(for kind: WatermarkTextLayerKind) -> EditableWatermarkTextLayer {
        switch kind {
        case .heading: heading
        case .body: body
        case .caption: caption
        }
    }

    public mutating func update(_ kind: WatermarkTextLayerKind, _ update: (inout EditableWatermarkTextLayer) -> Void) {
        switch kind {
        case .heading: update(&heading)
        case .body: update(&body)
        case .caption: update(&caption)
        }
    }

    public mutating func updateImage(_ update: (inout EditableWatermarkImageLayer) -> Void) {
        update(&image)
    }

    public mutating func setGlobalPosition(_ value: WatermarkPosition) {
        globalPosition = value
    }

    public mutating func setGlobalRotation(_ value: Double) {
        globalRotation = min(max(value.isFinite ? value : 0, -180), 180)
    }

    public mutating func setGlobalOpacity(_ value: Double) {
        globalOpacity = min(max(value.isFinite ? value : 1, 0), 1)
    }

    /// Returns the contract model without applying, exporting, or persisting
    /// it. Defaults preserve the version-1 shared schema and neutral global
    /// values for the deferred global-controls slice.
    public var watermarkConfig: WatermarkConfig {
        WatermarkConfig(
            automatic: false,
            heading: heading.watermarkTextLayer(),
            body: body.watermarkTextLayer(),
            caption: caption.watermarkTextLayer(),
            image: image.watermarkImageLayer(),
            globalPosition: globalPosition,
            globalRotation: globalRotation,
            globalOpacity: globalOpacity,
            layoutMode: layoutMode,
            tileSpacingX: tileSpacingX,
            tileSpacingY: tileSpacingY
        )
    }

    public var renderableLayersInCompositionOrder: [WatermarkEditorPreviewLayer] {
        [
            WatermarkEditorPreviewLayer(kind: .heading, layer: heading),
            WatermarkEditorPreviewLayer(kind: .body, layer: body),
            WatermarkEditorPreviewLayer(kind: .caption, layer: caption)
        ].filter(\.isRenderable)
    }
}

public struct WatermarkEditorPreviewLayer: Identifiable, Equatable, Sendable {
    public let kind: WatermarkTextLayerKind
    public let layer: EditableWatermarkTextLayer

    public var id: WatermarkTextLayerKind {
        kind
    }

    public var isRenderable: Bool {
        layer.isRenderable
    }

    public init(kind: WatermarkTextLayerKind, layer: EditableWatermarkTextLayer) {
        self.kind = kind
        self.layer = layer
    }
}

public enum WatermarkFontCatalog {
    /// Explicit Core Text family names shared with the renderer's catalog.
    /// System UI text deliberately has no serializable font-family entry here;
    /// a future system-font sentinel needs matching renderer support first.
    public static let supportedFontNames = ["Helvetica", "Times New Roman", "Courier"]
    public static let defaultFontName = "Helvetica"

    public static func sanitized(_ value: String) -> String {
        supportedFontNames.first { $0.caseInsensitiveCompare(value) == .orderedSame } ?? defaultFontName
    }
}

public enum WatermarkSemanticColor: String, CaseIterable, Identifiable, Sendable {
    case ink
    case brand
    case warning

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .ink: "Ink"
        case .brand: "Brand blue"
        case .warning: "Warning amber"
        }
    }

    /// These are watermark-content defaults, not UI component colors. UI
    /// chrome exclusively uses DesignSystem semantic tokens.
    public var hex: String {
        switch self {
        case .ink: "#0B1220"
        case .brand: "#1F4FEB"
        case .warning: "#F59E0B"
        }
    }
}

enum WatermarkHexColor {
    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withHash = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        guard withHash.count == 7, withHash.first == "#", withHash.dropFirst().allSatisfy(\.isHexDigit) else {
            return nil
        }
        return withHash.uppercased()
    }
}
