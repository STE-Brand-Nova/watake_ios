import Foundation

public struct NormalizedPoint: Sendable, Equatable, Codable {
    // swiftlint:disable:next identifier_name
    public var x: Double
    // swiftlint:disable:next identifier_name
    public var y: Double

    // swiftlint:disable:next identifier_name
    public init(x: Double, y: Double) {
        self.x = min(1.0, max(0.0, x))
        self.y = min(1.0, max(0.0, y))
    }

    public static let zero = NormalizedPoint(x: 0, y: 0)
    public static let unitTopLeft = NormalizedPoint(x: 0, y: 1)
    public static let unitTopRight = NormalizedPoint(x: 1, y: 1)
    public static let unitBottomRight = NormalizedPoint(x: 1, y: 0)
    public static let unitBottomLeft = NormalizedPoint(x: 0, y: 0)
}

public struct CropQuadrilateral: Sendable, Equatable, Codable {
    public var topLeft: NormalizedPoint
    public var topRight: NormalizedPoint
    public var bottomRight: NormalizedPoint
    public var bottomLeft: NormalizedPoint

    public init(
        topLeft: NormalizedPoint,
        topRight: NormalizedPoint,
        bottomRight: NormalizedPoint,
        bottomLeft: NormalizedPoint
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public static let unit = CropQuadrilateral(
        topLeft: .unitTopLeft,
        topRight: .unitTopRight,
        bottomRight: .unitBottomRight,
        bottomLeft: .unitBottomLeft
    )

    public var isUnitSquare: Bool {
        self == .unit
    }

    /// Checks that all four corners form a convex, non-degenerate, non-self-intersecting quadrilateral.
    public var isValid: Bool {
        let cp0 = crossProduct(bottomLeft, topLeft, topRight)
        let cp1 = crossProduct(topLeft, topRight, bottomRight)
        let cp2 = crossProduct(topRight, bottomRight, bottomLeft)
        let cp3 = crossProduct(bottomRight, bottomLeft, topLeft)

        let allPositive = cp0 > 0.0001 && cp1 > 0.0001 && cp2 > 0.0001 && cp3 > 0.0001
        let allNegative = cp0 < -0.0001 && cp1 < -0.0001 && cp2 < -0.0001 && cp3 < -0.0001

        return allPositive || allNegative
    }

    // swiftlint:disable:next identifier_name
    private func crossProduct(_ p1: NormalizedPoint, _ p2: NormalizedPoint, _ p3: NormalizedPoint) -> Double {
        (p2.x - p1.x) * (p3.y - p2.y) - (p2.y - p1.y) * (p3.x - p2.x)
    }
}
