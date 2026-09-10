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
        let width = min(max(0.08, start.width + translation.width / pageSize.width), 1)
        let height = min(max(0.04, start.height + translation.height / pageSize.height), 1)
        return AnnotationTransform(
            centerX: clampedCenter(start.centerX + (width - start.width) / 2),
            centerY: clampedCenter(start.centerY + (height - start.height) / 2),
            width: width,
            height: height,
            rotation: start.rotation
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
}
