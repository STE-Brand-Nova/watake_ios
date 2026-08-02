#if canImport(CoreImage) && canImport(Vision) && canImport(UIKit)
    import CoreImage
    import CoreImage.CIFilterBuiltins
    import UIKit
    import Vision

    public struct CropQuadrilateral: Sendable, Equatable {
        public var topLeft: CGPoint
        public var topRight: CGPoint
        public var bottomRight: CGPoint
        public var bottomLeft: CGPoint

        public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomRight = bottomRight
            self.bottomLeft = bottomLeft
        }

        public static let unit = CropQuadrilateral(
            topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1),
            bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 0)
        )
    }

    public struct RectificationResult: Sendable {
        public let quadrilateral: CropQuadrilateral
        public let isDetectionConfident: Bool

        public init(quadrilateral: CropQuadrilateral, isDetectionConfident: Bool) {
            self.quadrilateral = quadrilateral
            self.isDetectionConfident = isDetectionConfident
        }
    }

    /// Vision detects a candidate only. Callers always retain manual crop
    /// controls; uncertain and absent detections deliberately fall back to the
    /// full image rather than silently destroying source content.
    public actor DocumentRectifier {
        private let context = CIContext()

        public init() {}

        public func detect(in jpeg: Data) async -> RectificationResult {
            guard let image = UIImage(data: jpeg), let cgImage = image.cgImage else {
                return RectificationResult(quadrilateral: .unit, isDetectionConfident: false)
            }
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 1
            request.minimumConfidence = 0.65
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
                guard let rectangle = request.results?.first else {
                    return RectificationResult(quadrilateral: .unit, isDetectionConfident: false)
                }
                return RectificationResult(
                    quadrilateral: CropQuadrilateral(
                        topLeft: rectangle.topLeft, topRight: rectangle.topRight,
                        bottomRight: rectangle.bottomRight, bottomLeft: rectangle.bottomLeft
                    ),
                    isDetectionConfident: rectangle.confidence >= 0.8
                )
            } catch {
                return RectificationResult(quadrilateral: .unit, isDetectionConfident: false)
            }
        }

        public func rectify(jpeg: Data, quadrilateral: CropQuadrilateral) -> Data? {
            guard let image = CIImage(data: jpeg) else { return nil }
            let extent = image.extent
            let point: (CGPoint) -> CGPoint = { normalized in
                CGPoint(x: extent.minX + normalized.x * extent.width, y: extent.minY + normalized.y * extent.height)
            }
            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = image
            filter.topLeft = point(quadrilateral.topLeft)
            filter.topRight = point(quadrilateral.topRight)
            filter.bottomRight = point(quadrilateral.bottomRight)
            filter.bottomLeft = point(quadrilateral.bottomLeft)
            guard let output = filter.outputImage, let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95)
        }
    }
#endif
