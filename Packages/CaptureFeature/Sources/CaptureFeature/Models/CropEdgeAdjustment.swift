import WatakeDomain

enum CropEdge: CaseIterable, Hashable {
    case top, right, bottom, left

    var label: String {
        switch self {
        case .top: "Top crop edge"
        case .right: "Right crop edge"
        case .bottom: "Bottom crop edge"
        case .left: "Left crop edge"
        }
    }
}

enum CropEdgeAdjustment {
    static func moved(
        _ quad: CropQuadrilateral,
        edge: CropEdge,
        normalizedDelta: Double
    ) -> CropQuadrilateral {
        switch edge {
        case .top: movedTop(quad, by: normalizedDelta)
        case .right: movedRight(quad, by: normalizedDelta)
        case .bottom: movedBottom(quad, by: normalizedDelta)
        case .left: movedLeft(quad, by: normalizedDelta)
        }
    }

    private static func movedTop(_ quad: CropQuadrilateral, by delta: Double) -> CropQuadrilateral {
        let epsilon = 0.001
        let lowerBound = max(quad.bottomLeft.y, quad.bottomRight.y) + epsilon
        let offset = boundedOffset(
            delta,
            minimum: lowerBound - min(quad.topLeft.y, quad.topRight.y),
            maximum: 1 - max(quad.topLeft.y, quad.topRight.y)
        )
        return CropQuadrilateral(
            topLeft: NormalizedPoint(x: quad.topLeft.x, y: quad.topLeft.y + offset),
            topRight: NormalizedPoint(x: quad.topRight.x, y: quad.topRight.y + offset),
            bottomRight: quad.bottomRight,
            bottomLeft: quad.bottomLeft
        )
    }

    private static func movedBottom(_ quad: CropQuadrilateral, by delta: Double) -> CropQuadrilateral {
        let epsilon = 0.001
        let upperBound = min(quad.topLeft.y, quad.topRight.y) - epsilon
        let offset = boundedOffset(
            delta,
            minimum: -min(quad.bottomLeft.y, quad.bottomRight.y),
            maximum: upperBound - max(quad.bottomLeft.y, quad.bottomRight.y)
        )
        return CropQuadrilateral(
            topLeft: quad.topLeft,
            topRight: quad.topRight,
            bottomRight: NormalizedPoint(x: quad.bottomRight.x, y: quad.bottomRight.y + offset),
            bottomLeft: NormalizedPoint(x: quad.bottomLeft.x, y: quad.bottomLeft.y + offset)
        )
    }

    private static func movedRight(_ quad: CropQuadrilateral, by delta: Double) -> CropQuadrilateral {
        let epsilon = 0.001
        let lowerBound = max(quad.topLeft.x, quad.bottomLeft.x) + epsilon
        let offset = boundedOffset(
            delta,
            minimum: lowerBound - min(quad.topRight.x, quad.bottomRight.x),
            maximum: 1 - max(quad.topRight.x, quad.bottomRight.x)
        )
        return CropQuadrilateral(
            topLeft: quad.topLeft,
            topRight: NormalizedPoint(x: quad.topRight.x + offset, y: quad.topRight.y),
            bottomRight: NormalizedPoint(x: quad.bottomRight.x + offset, y: quad.bottomRight.y),
            bottomLeft: quad.bottomLeft
        )
    }

    private static func movedLeft(_ quad: CropQuadrilateral, by delta: Double) -> CropQuadrilateral {
        let epsilon = 0.001
        let upperBound = min(quad.topRight.x, quad.bottomRight.x) - epsilon
        let offset = boundedOffset(
            delta,
            minimum: -min(quad.topLeft.x, quad.bottomLeft.x),
            maximum: upperBound - max(quad.topLeft.x, quad.bottomLeft.x)
        )
        return CropQuadrilateral(
            topLeft: NormalizedPoint(x: quad.topLeft.x + offset, y: quad.topLeft.y),
            topRight: quad.topRight,
            bottomRight: quad.bottomRight,
            bottomLeft: NormalizedPoint(x: quad.bottomLeft.x + offset, y: quad.bottomLeft.y)
        )
    }

    private static func boundedOffset(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}
