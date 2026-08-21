import Foundation
import WatakeDomain

public enum WatermarkPreviewComposition: Equatable, Sendable {
    case textOnly
    case imageOnly
    case imageBehindText
    case imageAboveText
    case imageLeftOfText
    case imageRightOfText
}

public struct WatermarkEditorPreview: Equatable, Sendable {
    public let textLayers: [WatermarkEditorPreviewLayer]
    public let imageData: Data?
    public let imageLayer: EditableWatermarkImageLayer
    public let layoutMode: WatermarkLayoutMode
    public let tilePoints: [WatermarkTilePoint]
    public let globalPosition: WatermarkPosition
    public let globalRotation: Double
    public let globalOpacity: Double

    public init(draft: WatermarkEditorDraft, imageData: Data?) {
        textLayers = draft.renderableLayersInCompositionOrder
        self.imageData = imageData
        imageLayer = draft.image
        layoutMode = draft.layoutMode
        globalPosition = draft.globalPosition
        globalRotation = draft.globalRotation
        globalOpacity = draft.globalOpacity
        switch draft.layoutMode {
        case .single:
            tilePoints = [Self.point(for: draft.globalPosition)]
        case .tiled:
            if let tileSpacingX = draft.tileSpacingX, let tileSpacingY = draft.tileSpacingY {
                tilePoints = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: tileSpacingX, tileSpacingY: tileSpacingY)
            } else {
                tilePoints = []
            }
        }
    }

    private static func point(for position: WatermarkPosition) -> WatermarkTilePoint {
        switch position {
        case .topLeft: .init(normalizedX: 0.16, normalizedY: 0.16)
        case .topCenter: .init(normalizedX: 0.5, normalizedY: 0.16)
        case .topRight: .init(normalizedX: 0.84, normalizedY: 0.16)
        case .midLeft: .init(normalizedX: 0.16, normalizedY: 0.5)
        case .center: .init(normalizedX: 0.5, normalizedY: 0.5)
        case .midRight: .init(normalizedX: 0.84, normalizedY: 0.5)
        case .botLeft: .init(normalizedX: 0.16, normalizedY: 0.84)
        case .botCenter: .init(normalizedX: 0.5, normalizedY: 0.84)
        case .botRight: .init(normalizedX: 0.84, normalizedY: 0.84)
        }
    }

    public var tileCount: Int {
        tilePoints.count
    }

    public var hasRenderableImage: Bool {
        imageData != nil && imageLayer.isRenderable
    }

    public var composition: WatermarkPreviewComposition {
        guard hasRenderableImage else { return .textOnly }
        guard !textLayers.isEmpty else { return .imageOnly }
        switch imageLayer.placement {
        case .behindText: return .imageBehindText
        case .aboveText: return .imageAboveText
        case .leftOfText: return .imageLeftOfText
        case .rightOfText: return .imageRightOfText
        }
    }
}
