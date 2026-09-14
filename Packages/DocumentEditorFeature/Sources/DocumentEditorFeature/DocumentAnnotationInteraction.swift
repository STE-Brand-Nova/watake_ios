import CoreGraphics
import WatakeDomain

enum DocumentAnnotationInteraction {
    static let pageCoordinateSpace = "document-editor-page"

    static func moved(
        from start: AnnotationTransform,
        translation: CGSize,
        pageSize: CGSize
    ) -> AnnotationTransform {
        guard pageSize.width > 0, pageSize.height > 0 else { return start }
        return AnnotationTransform(
            centerX: clampedCenter(start.centerX + translation.width / pageSize.width),
            centerY: clampedCenter(start.centerY + translation.height / pageSize.height),
            width: start.width,
            height: start.height,
            rotation: start.rotation
        )
    }

    static func resized(
        from start: AnnotationTransform,
        translation: CGSize,
        pageSize: CGSize
    ) -> AnnotationTransform {
        guard pageSize.width > 0, pageSize.height > 0 else { return start }
        let radians = start.rotation * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let localX = cosine * translation.width + sine * translation.height
        let localY = -sine * translation.width + cosine * translation.height
        let width = min(max(0.08, start.width + localX / pageSize.width), 1)
        let height = min(max(0.04, start.height + localY / pageSize.height), 1)
        let localCenterShift = CGPoint(
            x: (width - start.width) * pageSize.width / 2,
            y: (height - start.height) * pageSize.height / 2
        )
        let pageCenterShift = CGPoint(
            x: cosine * localCenterShift.x - sine * localCenterShift.y,
            y: sine * localCenterShift.x + cosine * localCenterShift.y
        )
        return AnnotationTransform(
            centerX: clampedCenter(start.centerX + pageCenterShift.x / pageSize.width),
            centerY: clampedCenter(start.centerY + pageCenterShift.y / pageSize.height),
            width: width,
            height: height,
            rotation: start.rotation
        )
    }

    static func scaledAndRotated(
        from start: AnnotationTransform,
        scale: Double,
        rotationDelta: Double
    ) -> AnnotationTransform {
        AnnotationTransform(
            centerX: start.centerX,
            centerY: start.centerY,
            width: min(max(start.width * scale, 0.01), 1),
            height: min(max(start.height * scale, 0.01), 1),
            rotation: normalizedRotation(start.rotation + rotationDelta)
        )
    }

    static func rotated(
        from start: AnnotationTransform,
        startLocation: CGPoint,
        location: CGPoint,
        pageSize: CGSize
    ) -> AnnotationTransform {
        guard pageSize.width > 0, pageSize.height > 0 else { return start }
        let center = CGPoint(x: start.centerX * pageSize.width, y: start.centerY * pageSize.height)
        let startAngle = atan2(startLocation.y - center.y, startLocation.x - center.x)
        let currentAngle = atan2(location.y - center.y, location.x - center.x)
        var delta = currentAngle - startAngle
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta < -.pi {
            delta += 2 * .pi
        }
        return AnnotationTransform(
            centerX: start.centerX,
            centerY: start.centerY,
            width: start.width,
            height: start.height,
            rotation: normalizedRotation(start.rotation + delta * 180 / .pi)
        )
    }

    private static func clampedCenter(_ value: Double) -> Double {
        let snapped = abs(value - 0.5) <= 0.015 ? 0.5 : value
        return min(max(snapped, 0), 1)
    }

    private static func normalizedRotation(_ value: Double) -> Double {
        var output = value.truncatingRemainder(dividingBy: 360)
        if output > 180 {
            output -= 360
        } else if output < -180 {
            output += 360
        }
        return output
    }
}

enum DocumentEditorPalette {
    static let textColors = ["#0B1220", "#FFFFFF", "#1F4FEB", "#B91C1C", "#FBBF24"]
    static let strokeColors = ["#0B1220", "#1F4FEB", "#B91C1C", "#FBBF24"]
    static let highlightColors = ["#FBBF24", "#86EFAC", "#7DD3FC", "#F9A8D4", "#C4B5FD"]
    static let highlightWidthRange = 0.008 ... 0.06

    static func clampedHighlightWidth(_ width: Double) -> Double {
        min(max(width, highlightWidthRange.lowerBound), highlightWidthRange.upperBound)
    }

    static func colorName(for hex: String) -> String {
        switch hex.uppercased() {
        case "#0B1220": "Black"
        case "#FFFFFF": "White"
        case "#1F4FEB": "Blue"
        case "#B91C1C": "Red"
        case "#FBBF24": "Yellow"
        case "#86EFAC": "Green"
        case "#7DD3FC": "Light blue"
        case "#F9A8D4": "Pink"
        case "#C4B5FD": "Purple"
        default: "Custom"
        }
    }
}

enum HighlightLockAxis: Equatable {
    case horizontal
    case vertical
}

struct PreparedHighlight: Equatable {
    let transform: AnnotationTransform
    let stroke: InkStroke
}

enum DocumentHighlightInteraction {
    static let maximumCapturedPointCount = 10000
    private static let maximumStoredPointCount = 20000
    private static let minimumStrokeLength: Double = 4

    static func lockAxis(from first: InkPoint, to current: InkPoint) -> HighlightLockAxis {
        abs(current.location.x - first.location.x) >= abs(current.location.y - first.location.y)
            ? .horizontal
            : .vertical
    }

    static func displayedPoints(_ points: [InkPoint], axis: HighlightLockAxis?) -> [InkPoint] {
        guard let axis, let first = points.first, let last = points.last else { return points }
        let lockedLast = switch axis {
        case .horizontal:
            InkPoint(location: .init(x: last.location.x, y: first.location.y), pressure: last.pressure)
        case .vertical:
            InkPoint(location: .init(x: first.location.x, y: last.location.y), pressure: last.pressure)
        }
        return [first, lockedLast]
    }

    static func prepare(
        points: [InkPoint],
        pageSize: CGSize,
        width: Double,
        colorHex: String,
        opacity: Double
    ) -> PreparedHighlight? {
        guard points.count >= 2, pageSize.width > 0, pageSize.height > 0 else { return nil }
        let points = sampled(points, maximumCount: maximumStoredPointCount)
        guard pathLength(points, pageSize: pageSize) >= minimumStrokeLength else { return nil }
        let pageShortEdge = min(pageSize.width, pageSize.height)
        let width = DocumentEditorPalette.clampedHighlightWidth(width)
        let strokeRadius = max(1, width * pageShortEdge / 2)
        let selectionOutlineAllowance: Double = 2
        let paddingX = max((strokeRadius + selectionOutlineAllowance) / pageSize.width, 0.004)
        let paddingY = max((strokeRadius + selectionOutlineAllowance) / pageSize.height, 0.004)
        let locations = points.map(\.location)
        let xBounds = boundedRange(
            minimum: (locations.map(\.x).min() ?? 0) - paddingX,
            maximum: (locations.map(\.x).max() ?? 1) + paddingX
        )
        let yBounds = boundedRange(
            minimum: (locations.map(\.y).min() ?? 0) - paddingY,
            maximum: (locations.map(\.y).max() ?? 1) + paddingY
        )
        let minX = xBounds.lowerBound
        let maxX = xBounds.upperBound
        let minY = yBounds.lowerBound
        let maxY = yBounds.upperBound
        // Use an exact lower bound after subtracting the normalized endpoints.
        // Reconstructing 0.01 as `(lower + 0.01) - lower` can round below 0.01,
        // making the otherwise valid annotation fail domain validation and save.
        let boxWidth = max(0.01, maxX - minX)
        let boxHeight = max(0.01, maxY - minY)
        let localPoints = points.map { point in
            InkPoint(
                location: .init(
                    x: min(max((point.location.x - minX) / boxWidth, 0), 1),
                    y: min(max((point.location.y - minY) / boxHeight, 0), 1)
                ),
                pressure: point.pressure
            )
        }
        return PreparedHighlight(
            transform: AnnotationTransform(
                centerX: minX + boxWidth / 2,
                centerY: minY + boxHeight / 2,
                width: boxWidth,
                height: boxHeight
            ),
            stroke: InkStroke(
                points: localPoints,
                width: width,
                colorHex: colorHex,
                opacity: min(max(opacity, 0), 1)
            )
        )
    }

    static func appendCapturedPoint(_ point: InkPoint, to points: inout [InkPoint]) {
        if points.count >= maximumCapturedPointCount {
            points = points.enumerated().compactMap { index, point in
                index == 0 || index == points.count - 1 || index.isMultiple(of: 2) ? point : nil
            }
        }
        points.append(point)
    }

    private static func pathLength(_ points: [InkPoint], pageSize: CGSize) -> Double {
        zip(points, points.dropFirst()).reduce(0) { result, pair in
            let deltaX = (pair.1.location.x - pair.0.location.x) * pageSize.width
            let deltaY = (pair.1.location.y - pair.0.location.y) * pageSize.height
            return result + hypot(deltaX, deltaY)
        }
    }

    private static func sampled(_ points: [InkPoint], maximumCount: Int) -> [InkPoint] {
        guard points.count > maximumCount else { return points }
        let scale = Double(points.count - 1) / Double(maximumCount - 1)
        return (0 ..< maximumCount).map { index in
            points[Int((Double(index) * scale).rounded(.down))]
        }
    }

    private static func boundedRange(minimum: Double, maximum: Double) -> ClosedRange<Double> {
        var lower = min(max(minimum, 0), 1)
        var upper = min(max(maximum, 0), 1)
        if upper - lower < 0.01 {
            let midpoint = (lower + upper) / 2
            lower = min(max(midpoint - 0.005, 0), 0.99)
            upper = lower + 0.01
        }
        return lower ... upper
    }
}
