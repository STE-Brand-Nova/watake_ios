#if canImport(CoreImage) && canImport(Vision) && canImport(UIKit)
    import CoreImage
    import CoreImage.CIFilterBuiltins
    import UIKit
    import Vision
    import WatakeDomain

    /// Vision detects a candidate only. Callers always retain manual crop
    /// controls; uncertain and absent detections deliberately fall back to the
    /// full image rather than silently destroying source content.
    public actor DocumentRectifier: DocumentRectifying {
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
                        topLeft: NormalizedPoint(x: Double(rectangle.topLeft.x), y: Double(rectangle.topLeft.y)),
                        topRight: NormalizedPoint(x: Double(rectangle.topRight.x), y: Double(rectangle.topRight.y)),
                        bottomRight: NormalizedPoint(x: Double(rectangle.bottomRight.x), y: Double(rectangle.bottomRight.y)),
                        bottomLeft: NormalizedPoint(x: Double(rectangle.bottomLeft.x), y: Double(rectangle.bottomLeft.y))
                    ),
                    isDetectionConfident: rectangle.confidence >= 0.8
                )
            } catch {
                return RectificationResult(quadrilateral: .unit, isDetectionConfident: false)
            }
        }

        public func rectify(jpegData: Data, quadrilateral: CropQuadrilateral, rotationDegrees: Int) async -> Data? {
            if Task.isCancelled || !quadrilateral.isValid {
                return nil
            }
            guard let image = CIImage(data: jpegData) else { return nil }
            let extent = image.extent
            let point: (WatakeDomain.NormalizedPoint) -> CGPoint = { normalized in
                CGPoint(x: extent.minX + CGFloat(normalized.x) * extent.width, y: extent.minY + CGFloat(normalized.y) * extent.height)
            }
            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = image
            filter.topLeft = point(quadrilateral.topLeft)
            filter.topRight = point(quadrilateral.topRight)
            filter.bottomRight = point(quadrilateral.bottomRight)
            filter.bottomLeft = point(quadrilateral.bottomLeft)
            guard var output = filter.outputImage else { return nil }

            if Task.isCancelled {
                return nil
            }

            let normalizedRotation = (rotationDegrees % 360 + 360) % 360
            if normalizedRotation != 0 {
                let radians = CGFloat(normalizedRotation) * .pi / 180.0
                let transform = CGAffineTransform(rotationAngle: radians)
                output = output.transformed(by: transform)
            }

            if Task.isCancelled {
                return nil
            }
            guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95)
        }

        public func rectify(jpeg: Data, quadrilateral: CropQuadrilateral) -> Data? {
            guard quadrilateral.isValid, let image = CIImage(data: jpeg) else { return nil }
            let extent = image.extent
            let point: (WatakeDomain.NormalizedPoint) -> CGPoint = { normalized in
                CGPoint(x: extent.minX + CGFloat(normalized.x) * extent.width, y: extent.minY + CGFloat(normalized.y) * extent.height)
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
