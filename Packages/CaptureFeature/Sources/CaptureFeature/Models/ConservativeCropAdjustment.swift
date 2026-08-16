import WatakeDomain

/// Converts a Vision candidate into a crop that favors retaining document
/// edges over removing the surrounding background.
///
/// The balanced pass only accepts candidates it is fairly sure about. The
/// aggressive pass is user-initiated recovery for pages balanced could not
/// resolve, so it accepts weaker candidates — including the rectifier's
/// content-bounds estimate — and trims closer to the detected boundary.
enum ConservativeCropAdjustment {
    static let minimumDetectionConfidence = 0.65
    static let aggressiveMinimumDetectionConfidence = 0.35
    private static let outwardMargin = 0.025
    private static let aggressiveOutwardMargin = 0.008

    static func make(
        from detection: RectificationResult,
        strategy: DetectionStrategy = .balanced
    ) -> CropQuadrilateral? {
        let quadrilateral = detection.quadrilateral
        guard detection.confidence >= minimumConfidence(for: strategy) else { return nil }
        guard quadrilateral.isValid else { return nil }
        guard !quadrilateral.isUnitSquare else { return nil }

        let centerX = (quadrilateral.topLeft.x + quadrilateral.topRight.x
            + quadrilateral.bottomRight.x + quadrilateral.bottomLeft.x) / 4
        let centerY = (quadrilateral.topLeft.y + quadrilateral.topRight.y
            + quadrilateral.bottomRight.y + quadrilateral.bottomLeft.y) / 4
        let margin = outwardMargin(for: strategy)

        func outset(_ point: NormalizedPoint) -> NormalizedPoint {
            NormalizedPoint(
                x: point.x + (point.x - centerX) * margin,
                y: point.y + (point.y - centerY) * margin
            )
        }

        let adjusted = CropQuadrilateral(
            topLeft: outset(quadrilateral.topLeft),
            topRight: outset(quadrilateral.topRight),
            bottomRight: outset(quadrilateral.bottomRight),
            bottomLeft: outset(quadrilateral.bottomLeft)
        )
        guard adjusted.isValid else { return nil }
        // `NormalizedPoint` clamps to the unit square, so a candidate already
        // touching the image edge can survive the outset unchanged. Applying it
        // would report an adjustment the user cannot see, so treat an unchanged
        // quadrilateral as a genuinely trimming crop only when it differs from
        // a full-image crop.
        guard !adjusted.isUnitSquare else { return nil }
        return adjusted
    }

    private static func minimumConfidence(for strategy: DetectionStrategy) -> Double {
        switch strategy {
        case .balanced: minimumDetectionConfidence
        case .aggressive: aggressiveMinimumDetectionConfidence
        }
    }

    private static func outwardMargin(for strategy: DetectionStrategy) -> Double {
        switch strategy {
        case .balanced: outwardMargin
        case .aggressive: aggressiveOutwardMargin
        }
    }
}
