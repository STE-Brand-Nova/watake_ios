import Foundation

public enum GalleryGrouping: Sendable, Equatable, Codable {
    case oneDocument
    case separateDocuments
}

/// Encoded page values crossing boundaries. Neither UIKit nor persistence models
/// escape into this Sendable transaction.
public struct ImportedPage: Sendable, Equatable {
    public let sourceData: Data
    public let sourceMediaType: String
    public let sourceFileExtension: String
    public let rectifiedJPEG: Data?

    public init(
        sourceData: Data,
        sourceMediaType: String = "image/jpeg",
        sourceFileExtension: String = "jpg",
        rectifiedJPEG: Data? = nil
    ) {
        self.sourceData = sourceData
        self.sourceMediaType = sourceMediaType
        self.sourceFileExtension = sourceFileExtension
        self.rectifiedJPEG = rectifiedJPEG
    }
}

public struct RectificationResult: Sendable, Equatable {
    public let quadrilateral: CropQuadrilateral
    public let isDetectionConfident: Bool
    public let confidence: Double

    public init(
        quadrilateral: CropQuadrilateral,
        isDetectionConfident: Bool,
        confidence: Double = 0
    ) {
        self.quadrilateral = quadrilateral
        self.isDetectionConfident = isDetectionConfident
        self.confidence = min(1, max(0, confidence))
    }
}
