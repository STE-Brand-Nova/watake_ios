import Foundation

/// Pure, unit-testable page-geometry calculator for PDF export.
///
/// All sizing and placement decisions live here — outside SwiftUI and the PDF
/// drawing loop. Input and output use `Double` and domain value types so the
/// calculator has no Core Graphics or platform dependency.
///
/// ## Coordinate System
/// PDF uses a bottom-left origin. The calculator produces rectangles and
/// transforms in PDF coordinates. Source image dimensions are in pixels;
/// the `OriginalPageSizing` policy converts them to PDF points.
public enum ExportPageGeometry {
    /// Documented floating-point comparison tolerance for geometry tests.
    public static let tolerance = 1e-4

    // MARK: - Page Rectangle

    // swiftlint:disable identifier_name
    /// An axis-aligned rectangle in PDF points.
    public struct PageRect: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public static let zero = PageRect(x: 0, y: 0, width: 0, height: 0)
    }

    // swiftlint:enable identifier_name

    /// Scale, translation, and optional clip for drawing a source image
    /// into a content rectangle.
    public struct PageTransform: Equatable, Sendable {
        /// Uniform scale factor applied to the source image.
        public let scale: Double
        /// Horizontal translation in PDF points (after scaling).
        public let translateX: Double
        /// Vertical translation in PDF points (after scaling).
        public let translateY: Double
        /// Clip rectangle in PDF coordinates. For `fit`, matches `contentRect`.
        /// For `fill`, matches `contentRect` to enforce margin clipping.
        public let clipRect: PageRect

        public init(scale: Double, translateX: Double, translateY: Double, clipRect: PageRect) {
            self.scale = scale
            self.translateX = translateX
            self.translateY = translateY
            self.clipRect = clipRect
        }
    }

    // MARK: - EXIF Orientation

    /// Orientation-corrected display dimensions plus whether the axes were swapped.
    public struct AppliedOrientation: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public let isTransposed: Bool

        public init(width: Double, height: Double, isTransposed: Bool) {
            self.width = width
            self.height = height
            self.isTransposed = isTransposed
        }
    }

    /// Applies EXIF orientation to raw pixel dimensions, returning the
    /// effective (display) width and height plus whether the axes are swapped.
    ///
    /// EXIF orientations 5, 6, 7, 8 involve a 90° rotation that swaps width/height.
    public static func appliedOrientation(
        rawWidth: Double,
        rawHeight: Double,
        exifOrientation: Int
    ) -> AppliedOrientation {
        switch exifOrientation {
        case 5, 6, 7, 8:
            AppliedOrientation(width: rawHeight, height: rawWidth, isTransposed: true)
        default:
            AppliedOrientation(width: rawWidth, height: rawHeight, isTransposed: false)
        }
    }

    // MARK: - Media Box

    /// Computes the PDF media box for a given page size and source dimensions.
    ///
    /// - For `original`: uses the `OriginalPageSizing` policy (v1: 1 pixel = 1 PDF point).
    /// - For `a4` / `usLetter`: chooses portrait or landscape orientation based on the
    ///   source image's aspect ratio (after EXIF orientation).
    ///
    /// - Parameters:
    ///   - pageSize: The target page size.
    ///   - sourceWidth: Orientation-corrected source width in pixels.
    ///   - sourceHeight: Orientation-corrected source height in pixels.
    /// - Returns: Media box in PDF points with origin at (0, 0).
    public static func mediaBox(
        for pageSize: ExportPageSize,
        sourceWidth: Double,
        sourceHeight: Double
    ) -> PageRect {
        switch pageSize {
        case .original:
            // v1 policy: 1 pixel = 1 PDF point.
            return PageRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)

        case .a4, .usLetter:
            guard let dims = pageSize.portraitDimensions else {
                return .zero
            }
            let sourceIsLandscape = sourceWidth > sourceHeight
            if sourceIsLandscape {
                return PageRect(x: 0, y: 0, width: dims.height, height: dims.width)
            } else {
                return PageRect(x: 0, y: 0, width: dims.width, height: dims.height)
            }
        }
    }

    // MARK: - Content Rectangle

    /// Insets the media box by the given margin to produce the drawable content rectangle.
    ///
    /// - Throws: `ExportError.marginTooLarge` if the margin leaves no drawable area.
    public static func contentRect(
        mediaBox: PageRect,
        marginPoints: Double
    ) throws -> PageRect {
        let inset = max(0, marginPoints)
        let contentWidth = mediaBox.width - 2 * inset
        let contentHeight = mediaBox.height - 2 * inset
        guard contentWidth > 0, contentHeight > 0 else {
            throw ExportError.marginTooLarge(
                marginPoints: marginPoints,
                availableWidth: mediaBox.width,
                availableHeight: mediaBox.height
            )
        }
        return PageRect(
            x: mediaBox.x + inset,
            y: mediaBox.y + inset,
            width: contentWidth,
            height: contentHeight
        )
    }

    // MARK: - Fit Transform

    /// Computes the scale and translation to aspect-fit the source image
    /// inside the content rectangle. The image is centered; blank space is
    /// expected around the shorter axis.
    public static func fitTransform(
        sourceWidth: Double,
        sourceHeight: Double,
        contentRect: PageRect
    ) -> PageTransform {
        guard sourceWidth > 0, sourceHeight > 0 else {
            return PageTransform(scale: 1, translateX: contentRect.x, translateY: contentRect.y, clipRect: contentRect)
        }
        let scaleX = contentRect.width / sourceWidth
        let scaleY = contentRect.height / sourceHeight
        let scale = min(scaleX, scaleY)

        let scaledWidth = sourceWidth * scale
        let scaledHeight = sourceHeight * scale
        let translateX = contentRect.x + (contentRect.width - scaledWidth) / 2
        let translateY = contentRect.y + (contentRect.height - scaledHeight) / 2

        return PageTransform(scale: scale, translateX: translateX, translateY: translateY, clipRect: contentRect)
    }

    // MARK: - Fill Transform

    /// Computes the scale and translation to aspect-fill the content rectangle,
    /// center-cropping the source image. The clip rect enforces margin boundaries.
    public static func fillTransform(
        sourceWidth: Double,
        sourceHeight: Double,
        contentRect: PageRect
    ) -> PageTransform {
        guard sourceWidth > 0, sourceHeight > 0 else {
            return PageTransform(scale: 1, translateX: contentRect.x, translateY: contentRect.y, clipRect: contentRect)
        }
        let scaleX = contentRect.width / sourceWidth
        let scaleY = contentRect.height / sourceHeight
        let scale = max(scaleX, scaleY)

        let scaledWidth = sourceWidth * scale
        let scaledHeight = sourceHeight * scale
        let translateX = contentRect.x + (contentRect.width - scaledWidth) / 2
        let translateY = contentRect.y + (contentRect.height - scaledHeight) / 2

        return PageTransform(scale: scale, translateX: translateX, translateY: translateY, clipRect: contentRect)
    }

    // MARK: - Maximum Pixel Dimensions

    /// Returns the maximum pixel dimensions needed for a source image to render
    /// at the given page size and content rect, avoiding unnecessary decoding
    /// of pixels that will be clipped or downscaled.
    public static func maxPixelDimensions(
        sourceWidth: Double,
        sourceHeight: Double,
        contentRect: PageRect,
        fitMode: ExportFitMode
    ) -> (width: Int, height: Int) {
        guard sourceWidth > 0, sourceHeight > 0 else {
            return (width: 0, height: 0)
        }
        let transform: PageTransform = switch fitMode {
        case .fit:
            fitTransform(sourceWidth: sourceWidth, sourceHeight: sourceHeight, contentRect: contentRect)
        case .fill:
            fillTransform(sourceWidth: sourceWidth, sourceHeight: sourceHeight, contentRect: contentRect)
        }
        // At 1x scale, 1 PDF point = 1 pixel. The rendered size at the
        // transform's scale gives the needed pixels.
        let neededWidth = sourceWidth * transform.scale
        let neededHeight = sourceHeight * transform.scale
        // Add small margin for rounding.
        return (width: Int(ceil(neededWidth)), height: Int(ceil(neededHeight)))
    }
}
