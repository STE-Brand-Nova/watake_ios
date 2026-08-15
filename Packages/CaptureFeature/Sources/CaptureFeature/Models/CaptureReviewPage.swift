import Foundation
import WatakeDomain

/// Value type representing a page during the Capture Review flow.
public struct CaptureReviewPage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var sourceData: Data
    public var sourceMediaType: String
    public var sourceFileExtension: String
    public var rectifiedData: Data?
    public var cropQuadrilateral: CropQuadrilateral?
    public var rotationDegrees: Int // 0, 90, 180, 270
    public var detectionUncertain: Bool
    public var wasAutoCropAdjusted: Bool

    public init(
        id: UUID = UUID(),
        sourceData: Data,
        sourceMediaType: String = "image/jpeg",
        sourceFileExtension: String = "jpg",
        rectifiedData: Data? = nil,
        cropQuadrilateral: CropQuadrilateral? = nil,
        rotationDegrees: Int = 0,
        detectionUncertain: Bool = false,
        wasAutoCropAdjusted: Bool = false
    ) {
        self.id = id
        self.sourceData = sourceData
        self.sourceMediaType = sourceMediaType
        self.sourceFileExtension = sourceFileExtension
        self.rectifiedData = rectifiedData
        self.cropQuadrilateral = cropQuadrilateral
        self.rotationDegrees = (rotationDegrees % 360 + 360) % 360
        self.detectionUncertain = detectionUncertain
        self.wasAutoCropAdjusted = wasAutoCropAdjusted
    }

    /// The display image bytes to show in preview/thumbnails.
    /// Prefers `rectifiedData`, falling back to `sourceData`.
    public var displayData: Data {
        rectifiedData ?? sourceData
    }

    /// The SwiftUI visual rotation angle needed to render `displayData`.
    /// If `rectifiedData` is present, rotation is already rendered into its pixels (0° visual rotation).
    /// If falling back to `sourceData`, visual rotation applies `rotationDegrees`.
    public var visualRotationDegrees: Double {
        rectifiedData == nil ? Double(rotationDegrees) : 0.0
    }
}
