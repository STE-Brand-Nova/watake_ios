import WatakeDomain

/// Converts a moderately reliable Vision candidate into a crop that favors
/// retaining document edges over removing the surrounding background.
enum ConservativeCropAdjustment {
    static let minimumDetectionConfidence = 0.65
    private static let outwardMargin = 0.025

    static func make(from detection: RectificationResult) -> CropQuadrilateral? {
        let quadrilateral = detection.quadrilateral
        guard detection.confidence >= minimumDetectionConfidence else { return nil }
        guard quadrilateral.isValid else { return nil }
        guard !quadrilateral.isUnitSquare else { return nil }

        let centerX = (quadrilateral.topLeft.x + quadrilateral.topRight.x
            + quadrilateral.bottomRight.x + quadrilateral.bottomLeft.x) / 4
        let centerY = (quadrilateral.topLeft.y + quadrilateral.topRight.y
            + quadrilateral.bottomRight.y + quadrilateral.bottomLeft.y) / 4

        func outset(_ point: NormalizedPoint) -> NormalizedPoint {
            NormalizedPoint(
                x: point.x + (point.x - centerX) * outwardMargin,
                y: point.y + (point.y - centerY) * outwardMargin
            )
        }

        let adjusted = CropQuadrilateral(
            topLeft: outset(quadrilateral.topLeft),
            topRight: outset(quadrilateral.topRight),
            bottomRight: outset(quadrilateral.bottomRight),
            bottomLeft: outset(quadrilateral.bottomLeft)
        )
        return adjusted.isValid ? adjusted : nil
    }
}
