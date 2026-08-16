import Foundation
import WatakeDomain

/// Bytes and media metadata shared by Photos and Files imports.
public struct CaptureImportMedia: Sendable, Equatable {
    public let data: Data
    public let mediaType: String
    public let fileExtension: String

    public init(data: Data, mediaType: String, fileExtension: String) {
        self.data = data
        self.mediaType = mediaType
        self.fileExtension = fileExtension
    }
}

/// Converts every imported source into the same review-page model and applies
/// existing document detection/rectification behavior.
public struct CaptureImportPipeline: Sendable {
    private let rectifier: any DocumentRectifying

    public init(rectifier: any DocumentRectifying) {
        self.rectifier = rectifier
    }

    public func makePages(from media: [CaptureImportMedia]) async -> [CaptureReviewPage] {
        var pages: [CaptureReviewPage] = []
        pages.reserveCapacity(media.count)
        for item in media {
            if Task.isCancelled {
                return []
            }
            let detection = await rectifier.detect(in: item.data)
            if Task.isCancelled {
                return []
            }
            let rectified = detection.isDetectionConfident
                ? await rectifier.rectify(
                    jpegData: item.data,
                    quadrilateral: detection.quadrilateral,
                    rotationDegrees: 0
                )
                : nil
            if Task.isCancelled {
                return []
            }
            pages.append(CaptureReviewPage(
                sourceData: item.data,
                sourceMediaType: item.mediaType,
                sourceFileExtension: item.fileExtension,
                rectifiedData: rectified,
                cropQuadrilateral: detection.quadrilateral,
                rotationDegrees: 0,
                detectionUncertain: !detection.isDetectionConfident
            ))
        }
        return pages
    }
}
