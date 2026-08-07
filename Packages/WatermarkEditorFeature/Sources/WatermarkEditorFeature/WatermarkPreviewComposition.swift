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

    public init(draft: WatermarkEditorDraft, imageData: Data?) {
        textLayers = draft.renderableLayersInCompositionOrder
        self.imageData = imageData
        imageLayer = draft.image
        layoutMode = draft.layoutMode
        switch draft.layoutMode {
        case .single:
            tilePoints = [WatermarkTilePoint(normalizedX: 0.5, normalizedY: 0.5)]
        case .tiled:
            if let tileSpacingX = draft.tileSpacingX, let tileSpacingY = draft.tileSpacingY {
                tilePoints = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: tileSpacingX, tileSpacingY: tileSpacingY)
            } else {
                tilePoints = []
            }
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
