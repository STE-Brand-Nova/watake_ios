import Foundation
import WatakeDomain

/// Codable image-layer metadata. Selected bytes remain in `WatermarkEditorModel`
/// and are never encoded, persisted, or sent to an asset store in this slice.
public struct EditableWatermarkImageLayer: Codable, Equatable, Sendable {
    public private(set) var enabled: Bool
    public private(set) var assetReference: AssetReference?
    public private(set) var scale: Double
    public private(set) var tintHex: String?
    public private(set) var rotation: Double
    public private(set) var opacity: Double
    public private(set) var placement: WatermarkImagePlacement

    public init(
        enabled: Bool = true,
        assetReference: AssetReference? = nil,
        scale: Double = 1,
        tintHex: String? = nil,
        rotation: Double = 0,
        opacity: Double = 1,
        placement: WatermarkImagePlacement = .behindText
    ) {
        self.enabled = enabled
        self.assetReference = assetReference
        self.scale = Self.clampedScale(scale)
        self.tintHex = tintHex.flatMap(WatermarkHexColor.normalized)
        self.rotation = Self.clampedRotation(rotation)
        self.opacity = Self.clampedOpacity(opacity)
        self.placement = placement
    }

    public var isRenderable: Bool {
        enabled && assetReference != nil
    }

    public func watermarkImageLayer() -> WatermarkImageLayer? {
        guard let assetReference else { return nil }
        return WatermarkImageLayer(
            enabled: enabled,
            assetRef: assetReference,
            scale: scale,
            tintHex: tintHex,
            rotation: rotation,
            opacity: opacity,
            placement: placement
        )
    }

    public mutating func setAssetReference(_ value: AssetReference) {
        assetReference = value
    }

    public mutating func clearAssetReference() {
        assetReference = nil
    }

    public mutating func setEnabled(_ value: Bool) {
        enabled = value
    }

    public mutating func setScale(_ value: Double) {
        scale = Self.clampedScale(value)
    }

    public mutating func setRotation(_ value: Double) {
        rotation = Self.clampedRotation(value)
    }

    public mutating func setOpacity(_ value: Double) {
        opacity = Self.clampedOpacity(value)
    }

    public mutating func setPlacement(_ value: WatermarkImagePlacement) {
        placement = value
    }

    /// Invalid input leaves active tint untouched, so preview stays safe.
    public mutating func setTintHex(_ value: String?) {
        guard let value else {
            tintHex = nil
            return
        }
        guard let normalized = WatermarkHexColor.normalized(value) else { return }
        tintHex = normalized
    }

    private static func clampedScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0.1), 3)
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
