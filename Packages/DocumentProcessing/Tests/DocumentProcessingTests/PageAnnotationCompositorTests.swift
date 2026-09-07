import CoreGraphics
import Foundation
import ImageIO
import Testing
import WatakeDomain
@testable import DocumentProcessing

@Suite("Page annotation compositor")
struct PageAnnotationCompositorTests {
    @Test("renders annotations at source resolution and honors z-order")
    func rendersAtSourceResolutionAndHonorsZOrder() async throws {
        let store = InMemoryAssetStore()
        let sourceData = SyntheticImage.makePNGData(width: 120, height: 80, red: 1, green: 1, blue: 1)
        let redData = SyntheticImage.makePNGData(width: 40, height: 40, red: 1, green: 0, blue: 0)
        let blueData = SyntheticImage.makePNGData(width: 40, height: 40, red: 0, green: 0, blue: 1)
        let red = SyntheticImage.makeAssetReference(pageId: UUID(), data: redData)
        let blue = SyntheticImage.makeAssetReference(pageId: UUID(), data: blueData)
        await store.seed(redData, reference: red)
        await store.seed(blueData, reference: blue)
        let transform = AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.5, height: 0.75)
        let annotations = [
            PageAnnotation(id: UUID(), kind: .image, transform: transform, zIndex: 0, image: red),
            PageAnnotation(id: UUID(), kind: .image, transform: transform, zIndex: 1, image: blue)
        ]

        let result = try await PageAnnotationCompositor(assetStore: store).renderJPEG(
            sourceData: sourceData,
            annotations: annotations
        )
        let rendered = try decodeImage(result)
        let center = try pixel(in: rendered, column: rendered.width / 2, row: rendered.height / 2)

        #expect(rendered.width == 120)
        #expect(rendered.height == 80)
        #expect(center.blue > 0.8)
        #expect(center.red < 0.2)
    }

    @Test("renders text, signature, and highlight layers into a bounded preview")
    func rendersVectorLayersIntoBoundedPreview() async throws {
        let store = InMemoryAssetStore()
        let sourceData = SyntheticImage.makePNGData(width: 240, height: 160, red: 1, green: 1, blue: 1)
        let stroke = InkStroke(
            points: [
                InkPoint(location: NormalizedPoint(x: 0, y: 0.5)),
                InkPoint(location: NormalizedPoint(x: 1, y: 0.5))
            ],
            width: 0.04,
            colorHex: "#FFCC00",
            opacity: 0.5
        )
        let annotations = vectorAnnotations(highlight: stroke)

        let result = try await PageAnnotationCompositor(assetStore: store).renderJPEG(
            sourceData: sourceData,
            annotations: annotations,
            maximumPixelDimension: 120
        )
        let rendered = try decodeImage(result)

        #expect(rendered.width == 120)
        #expect(rendered.height == 80)
        #expect(result != sourceData)
    }
}

private struct RGBPixel {
    let red: Double
    let green: Double
    let blue: Double
}

private func decodeImage(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw PageAnnotationRenderError.sourceUndecodable
    }
    return image
}

private func pixel(in image: CGImage, column: Int, row: Int) throws -> RGBPixel {
    var bytes = [UInt8](repeating: 0, count: 4)
    guard let context = CGContext(
        data: &bytes,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw PageAnnotationRenderError.contextUnavailable
    }
    context.interpolationQuality = .none
    context.translateBy(x: CGFloat(-column), y: CGFloat(-(image.height - row - 1)))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return RGBPixel(
        red: Double(bytes[0]) / 255,
        green: Double(bytes[1]) / 255,
        blue: Double(bytes[2]) / 255
    )
}

private func vectorAnnotations(highlight: InkStroke) -> [PageAnnotation] {
    [
        PageAnnotation(
            id: UUID(),
            kind: .text,
            transform: AnnotationTransform(centerX: 0.5, centerY: 0.25, width: 0.8, height: 0.2),
            zIndex: 0,
            text: AnnotationText(text: "Approved", fontSize: 0.08, colorHex: "#0B1220")
        ),
        PageAnnotation(
            id: UUID(),
            kind: .signature,
            transform: AnnotationTransform(centerX: 0.5, centerY: 0.55, width: 0.5, height: 0.2),
            zIndex: 1,
            strokes: [
                InkStroke(
                    points: [
                        InkPoint(location: NormalizedPoint(x: 0.1, y: 0.8)),
                        InkPoint(location: NormalizedPoint(x: 0.9, y: 0.2))
                    ],
                    width: 0.02,
                    colorHex: "#0B1220"
                )
            ]
        ),
        PageAnnotation(
            id: UUID(),
            kind: .highlight,
            transform: AnnotationTransform(centerX: 0.5, centerY: 0.8, width: 0.8, height: 0.15),
            zIndex: 2,
            strokes: [highlight]
        )
    ]
}
