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

enum ImageResizeCorner: CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var horizontalSign: Double {
        switch self {
        case .topLeading, .bottomLeading: -1
        case .topTrailing, .bottomTrailing: 1
        }
    }

    var verticalSign: Double {
        switch self {
        case .topLeading, .topTrailing: -1
        case .bottomLeading, .bottomTrailing: 1
        }
    }

    var accessibilityName: String {
        switch self {
        case .topLeading: "top left"
        case .topTrailing: "top right"
        case .bottomLeading: "bottom left"
        case .bottomTrailing: "bottom right"
        }
    }
}

enum DocumentImageInteraction {
    static let placementTapThreshold: Double = 12
    static let rotationSnapThreshold: Double = 7

    static func placement(
        from start: CGPoint,
        to end: CGPoint,
        imageAspectRatio: Double,
        pageSize: CGSize
    ) -> AnnotationTransform {
        guard pageSize.width > 0, pageSize.height > 0, imageAspectRatio.isFinite, imageAspectRatio > 0 else {
            return AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.4, height: 0.3)
        }
        let start = clamped(start, to: pageSize)
        let end = clamped(end, to: pageSize)
        let deltaX = abs(end.x - start.x)
        let deltaY = abs(end.y - start.y)
        guard hypot(deltaX, deltaY) >= placementTapThreshold,
              deltaX >= max(4, pageSize.width * 0.01),
              deltaY >= max(4, pageSize.height * 0.01) else {
            return defaultPlacement(at: end, imageAspectRatio: imageAspectRatio, pageSize: pageSize)
        }

        let width = min(deltaX, deltaY * imageAspectRatio)
        let height = width / imageAspectRatio
        guard width >= max(4, pageSize.width * 0.01),
              height >= max(4, pageSize.height * 0.01) else {
            return defaultPlacement(at: end, imageAspectRatio: imageAspectRatio, pageSize: pageSize)
        }
        let horizontalDirection: CGFloat = end.x >= start.x ? 1 : -1
        let verticalDirection: CGFloat = end.y >= start.y ? 1 : -1
        let opposite = CGPoint(
            x: start.x + horizontalDirection * width,
            y: start.y + verticalDirection * height
        )
        return normalizedRect(
            center: CGPoint(x: (start.x + opposite.x) / 2, y: (start.y + opposite.y) / 2),
            size: CGSize(width: width, height: height),
            pageSize: pageSize
        )
    }

    static func defaultPlacement(
        at location: CGPoint,
        imageAspectRatio: Double,
        pageSize: CGSize
    ) -> AnnotationTransform {
        guard pageSize.width > 0, pageSize.height > 0, imageAspectRatio.isFinite, imageAspectRatio > 0 else {
            return AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.4, height: 0.3)
        }
        let aspectRatio = CGFloat(imageAspectRatio)
        let maximumWidth = pageSize.width * 0.42
        let maximumHeight = pageSize.height * 0.42
        var width = min(maximumWidth, maximumHeight * aspectRatio)
        var height = width / aspectRatio
        if width < pageSize.width * 0.01 {
            width = pageSize.width * 0.01
            height = width / aspectRatio
        }
        if height < pageSize.height * 0.01 {
            height = pageSize.height * 0.01
            width = height * aspectRatio
        }
        if width > pageSize.width {
            width = pageSize.width
            height = width / aspectRatio
        }
        if height > pageSize.height {
            height = pageSize.height
            width = height * aspectRatio
        }
        let halfWidth = width / 2
        let halfHeight = height / 2
        let center = CGPoint(
            x: min(max(location.x, halfWidth), pageSize.width - halfWidth),
            y: min(max(location.y, halfHeight), pageSize.height - halfHeight)
        )
        return normalizedRect(center: center, size: CGSize(width: width, height: height), pageSize: pageSize)
    }

    static func resized(
        from start: AnnotationTransform,
        corner: ImageResizeCorner,
        location: CGPoint,
        pageSize: CGSize
    ) -> AnnotationTransform {
        guard pageSize.width > 0, pageSize.height > 0 else { return start }
        let width = start.width * pageSize.width
        let height = start.height * pageSize.height
        let diagonal = CGPoint(
            x: corner.horizontalSign * width,
            y: corner.verticalSign * height
        )
        let radians = start.rotation * .pi / 180
        let anchorOffset = rotate(CGPoint(x: -diagonal.x / 2, y: -diagonal.y / 2), radians: radians)
        let center = CGPoint(x: start.centerX * pageSize.width, y: start.centerY * pageSize.height)
        let anchor = CGPoint(x: center.x + anchorOffset.x, y: center.y + anchorOffset.y)
        let pointer = CGPoint(x: location.x - anchor.x, y: location.y - anchor.y)
        let localPointer = rotate(pointer, radians: -radians)
        let denominator = diagonal.x * diagonal.x + diagonal.y * diagonal.y
        guard denominator > 0 else { return start }
        var scale = (localPointer.x * diagonal.x + localPointer.y * diagonal.y) / denominator
        let minimumScale = max(28 / width, 28 / height, 0.01 / start.width, 0.01 / start.height)
        let unscaledCenterOffset = rotate(
            CGPoint(x: diagonal.x / 2, y: diagonal.y / 2),
            radians: radians
        )
        let maximumScale = min(
            1 / start.width,
            1 / start.height,
            scaleLimit(anchor: anchor.x, offset: unscaledCenterOffset.x, maximum: pageSize.width),
            scaleLimit(anchor: anchor.y, offset: unscaledCenterOffset.y, maximum: pageSize.height)
        )
        scale = min(max(scale, minimumScale), maximumScale)

        let newWidth = start.width * scale
        let newHeight = start.height * scale
        let newDiagonal = CGPoint(
            x: corner.horizontalSign * newWidth * pageSize.width,
            y: corner.verticalSign * newHeight * pageSize.height
        )
        let centerOffset = rotate(CGPoint(x: newDiagonal.x / 2, y: newDiagonal.y / 2), radians: radians)
        return AnnotationTransform(
            centerX: (anchor.x + centerOffset.x) / pageSize.width,
            centerY: (anchor.y + centerOffset.y) / pageSize.height,
            width: newWidth,
            height: newHeight,
            rotation: start.rotation
        )
    }

    static func rotated(
        from start: AnnotationTransform,
        startLocation: CGPoint,
        location: CGPoint,
        pageSize: CGSize
    ) -> AnnotationTransform {
        let rotated = DocumentAnnotationInteraction.rotated(
            from: start,
            startLocation: startLocation,
            location: location,
            pageSize: pageSize
        )
        return AnnotationTransform(
            centerX: rotated.centerX,
            centerY: rotated.centerY,
            width: rotated.width,
            height: rotated.height,
            rotation: snappedRotation(rotated.rotation)
        )
    }

    static func snappedRotation(_ rotation: Double) -> Double {
        let normalized = normalize(rotation)
        let candidates = [-180.0, -90, 0, 90, 180]
        guard let closest = candidates.min(by: { abs(normalized - $0) < abs(normalized - $1) }),
              abs(normalized - closest) <= rotationSnapThreshold else { return normalized }
        return closest == 180 ? -180 : closest
    }

    private static func normalizedRect(center: CGPoint, size: CGSize, pageSize: CGSize) -> AnnotationTransform {
        AnnotationTransform(
            centerX: min(max(center.x / pageSize.width, 0), 1),
            centerY: min(max(center.y / pageSize.height, 0), 1),
            width: min(max(size.width / pageSize.width, 0.01), 1),
            height: min(max(size.height / pageSize.height, 0.01), 1)
        )
    }

    private static func clamped(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }

    private static func rotate(_ point: CGPoint, radians: Double) -> CGPoint {
        CGPoint(
            x: cos(radians) * point.x - sin(radians) * point.y,
            y: sin(radians) * point.x + cos(radians) * point.y
        )
    }

    private static func scaleLimit(anchor: CGFloat, offset: CGFloat, maximum: CGFloat) -> Double {
        if offset > 0 {
            return max(0, (maximum - anchor) / offset)
        }
        if offset < 0 {
            return max(0, -anchor / offset)
        }
        return .greatestFiniteMagnitude
    }

    private static func normalize(_ value: Double) -> Double {
        var output = value.truncatingRemainder(dividingBy: 360)
        if output > 180 {
            output -= 360
        }
        if output < -180 {
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
