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
            await detect(in: jpeg, strategy: .balanced)
        }

        public func detect(in jpeg: Data, strategy: DetectionStrategy) async -> RectificationResult {
            guard let image = UIImage(data: jpeg), let cgImage = image.cgImage else {
                return RectificationResult(quadrilateral: .unit, isDetectionConfident: false)
            }
            if let rectangle = detectRectangle(in: cgImage, strategy: strategy) {
                return RectificationResult(
                    quadrilateral: CropQuadrilateral(
                        topLeft: NormalizedPoint(x: Double(rectangle.topLeft.x), y: Double(rectangle.topLeft.y)),
                        topRight: NormalizedPoint(x: Double(rectangle.topRight.x), y: Double(rectangle.topRight.y)),
                        bottomRight: NormalizedPoint(x: Double(rectangle.bottomRight.x), y: Double(rectangle.bottomRight.y)),
                        bottomLeft: NormalizedPoint(x: Double(rectangle.bottomLeft.x), y: Double(rectangle.bottomLeft.y))
                    ),
                    isDetectionConfident: rectangle.confidence >= 0.8,
                    confidence: Double(rectangle.confidence)
                )
            }
            guard strategy == .aggressive, let bounds = contentBounds(of: cgImage) else {
                return RectificationResult(quadrilateral: .unit, isDetectionConfident: false)
            }
            return RectificationResult(
                quadrilateral: bounds,
                isDetectionConfident: false,
                confidence: contentBoundsConfidence
            )
        }

        /// Confidence reported for a content-bounds estimate. High enough to
        /// clear the aggressive adjustment threshold, deliberately below the
        /// balanced threshold so this estimate never resolves an import
        /// automatically without the user asking for it.
        private var contentBoundsConfidence: Double {
            0.4
        }

        private func detectRectangle(
            in cgImage: CGImage,
            strategy: DetectionStrategy
        ) -> VNRectangleObservation? {
            let request = VNDetectRectanglesRequest()
            switch strategy {
            case .balanced:
                request.maximumObservations = 1
                request.minimumConfidence = 0.65
            case .aggressive:
                // A page the balanced pass rejected is usually skewed, low
                // contrast, or cropped tight by the scanner. Widen every axis
                // Vision filters on, then choose by area instead of order.
                request.maximumObservations = 8
                request.minimumConfidence = 0.2
                request.minimumAspectRatio = 0.2
                request.maximumAspectRatio = 1.0
                request.minimumSize = 0.15
                request.quadratureTolerance = 45
            }
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                return nil
            }
            guard let observations = request.results, !observations.isEmpty else { return nil }
            if strategy == .balanced {
                return observations.first
            }
            return observations.max { area(of: $0) < area(of: $1) }
        }

        /// Shoelace area of the observation's own corners. `boundingBox` would
        /// overstate a skewed page, which is exactly the case aggressive mode
        /// exists to handle.
        private func area(of observation: VNRectangleObservation) -> CGFloat {
            let corners = [
                observation.topLeft,
                observation.topRight,
                observation.bottomRight,
                observation.bottomLeft
            ]
            var total: CGFloat = 0
            for index in corners.indices {
                let current = corners[index]
                let next = corners[(index + 1) % corners.count]
                total += current.x * next.y - next.x * current.y
            }
            return abs(total) / 2
        }

        // MARK: - Content Bounds Fallback

        /// Axis-aligned bounds of the non-background content, in Vision's
        /// bottom-left normalized space. Used only when aggressive rectangle
        /// detection finds no edges at all — the common bulk-import case of a
        /// scan already trimmed to a plain background, where there is no
        /// document *edge* to detect but plenty of content to bound.
        private func contentBounds(of cgImage: CGImage) -> CropQuadrilateral? {
            let width = 96
            let height = 96
            var pixels = [UInt8](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let threshold = contentThreshold(for: pixels) else { return nil }

            var minX = width
            var maxX = -1
            var minY = height
            var maxY = -1
            for row in 0 ..< height {
                for column in 0 ..< width where pixels[row * width + column] < threshold {
                    minX = min(minX, column)
                    maxX = max(maxX, column)
                    minY = min(minY, row)
                    maxY = max(maxY, row)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }

            // A box covering nearly everything means the crop would change
            // nothing; report failure so the page stays honestly unresolved.
            let coverage = Double((maxX - minX + 1) * (maxY - minY + 1)) / Double(width * height)
            guard coverage < 0.97, coverage > 0.02 else { return nil }

            let padding = 2.0
            let left = max(0, Double(minX) - padding) / Double(width)
            let right = min(Double(width), Double(maxX + 1) + padding) / Double(width)
            // CGContext rows run top-down; Vision's normalized space runs bottom-up.
            let top = 1.0 - max(0, Double(minY) - padding) / Double(height)
            let bottom = 1.0 - min(Double(height), Double(maxY + 1) + padding) / Double(height)

            let quadrilateral = CropQuadrilateral(
                topLeft: NormalizedPoint(x: left, y: top),
                topRight: NormalizedPoint(x: right, y: top),
                bottomRight: NormalizedPoint(x: right, y: bottom),
                bottomLeft: NormalizedPoint(x: left, y: bottom)
            )
            return quadrilateral.isValid ? quadrilateral : nil
        }

        /// Midpoint between the background mode and the darkest content, so the
        /// threshold adapts to grey scans instead of assuming white paper.
        private func contentThreshold(for pixels: [UInt8]) -> UInt8? {
            var histogram = [Int](repeating: 0, count: 256)
            for pixel in pixels {
                histogram[Int(pixel)] += 1
            }
            guard let background = histogram.indices.max(by: { histogram[$0] < histogram[$1] }) else { return nil }
            guard let darkest = histogram.indices.first(where: { histogram[$0] > 0 }) else { return nil }
            let separation = background - darkest
            // Nearly uniform image: no content to bound.
            guard separation > 24 else { return nil }
            return UInt8(darkest + separation / 2)
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
