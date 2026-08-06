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

    public init(draft: WatermarkEditorDraft, imageData: Data?) {
        textLayers = draft.renderableLayersInCompositionOrder
        self.imageData = imageData
        imageLayer = draft.image
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
