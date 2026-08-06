import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import WatakeDomain
@testable import WatermarkEditorFeature

struct WatermarkImageLayerTests {
    @Test func imageDefaultsAreSafeAndCodable() throws {
        let layer = EditableWatermarkImageLayer()

        #expect(layer.enabled)
        #expect(layer.assetReference == nil)
        #expect(layer.scale == 1)
        #expect(layer.tintHex == nil)
        #expect(!layer.isRenderable)
        #expect(try JSONDecoder().decode(EditableWatermarkImageLayer.self, from: JSONEncoder().encode(layer)) == layer)
    }

    @Test func imageCodableRoundTripPreservesSharedContractFields() throws {
        let layer = EditableWatermarkImageLayer(
            enabled: false,
            assetReference: testReference(),
            scale: 2.2,
            tintHex: "#1f4feb",
            rotation: -45,
            opacity: 0.35,
            placement: .leftOfText
        )

        let decoded = try JSONDecoder().decode(EditableWatermarkImageLayer.self, from: JSONEncoder().encode(layer))

        #expect(decoded == layer)
        #expect(decoded.watermarkImageLayer()?.tintHex == "#1F4FEB")
        #expect(decoded.watermarkImageLayer()?.placement == .leftOfText)
    }

    @Test func imageBoundaryClampsAndRetainsSafeTint() {
        var layer = EditableWatermarkImageLayer(scale: -1, tintHex: "#1F4FEB", rotation: 400, opacity: -1)

        #expect(layer.scale == 0.1)
        #expect(layer.rotation == 180)
        #expect(layer.opacity == 0)
        layer.setScale(.infinity)
        layer.setRotation(-.infinity)
        layer.setOpacity(.nan)
        layer.setTintHex("invalid")

        #expect(layer.scale == 1)
        #expect(layer.rotation == 0)
        #expect(layer.opacity == 1)
        #expect(layer.tintHex == "#1F4FEB")
    }

    @Test func importerAcceptsPNGAndJPEGWithAccurateReferences() async throws {
        for (type, expectedType, expectedExtension) in [
            (UTType.png, "image/png", "png"),
            (UTType.jpeg, "image/jpeg", "jpg")
        ] {
            let data = try encodedImage(type: type)
            let imported = try await WatermarkImageImporter().importImage(data: data)

            #expect(imported.data == data)
            #expect(imported.assetReference.mediaType == expectedType)
            #expect(imported.assetReference.relativePath.hasSuffix(".\(expectedExtension)"))
            #expect(imported.assetReference.relativePath.hasPrefix("watermark-assets/"))
            #expect(imported.assetReference.byteSize == data.count)
            #expect(imported.assetReference.sha256Hex == SHA256.hash(data: data).hexString)
        }
    }

    @Test func importerRejectsUndecodableAndUnsupportedImages() async throws {
        await #expect(throws: WatermarkImageImportError.undecodable) {
            try await WatermarkImageImporter().importImage(data: Data("not an image".utf8))
        }
        await #expect(throws: WatermarkImageImportError.unsupportedMediaType) {
            try await WatermarkImageImporter().importImage(data: encodedImage(type: .gif))
        }
        await #expect(throws: WatermarkImageImportError.unreasonableSize) {
            try await WatermarkImageImporter().importImage(
                data: Data(repeating: 0, count: WatermarkImageImporter.maximumByteCount + 1)
            )
        }
    }

    @Test func imagePlacementCompositionIsDeterministic() {
        let reference = testReference()
        var draft = WatermarkEditorDraft(
            heading: .init(text: "Heading", enabled: true),
            image: .init(assetReference: reference, placement: .behindText)
        )

        #expect(WatermarkEditorPreview(draft: draft, imageData: Data([1])).composition == .imageBehindText)
        draft.updateImage { $0.setPlacement(.aboveText) }
        #expect(WatermarkEditorPreview(draft: draft, imageData: Data([1])).composition == .imageAboveText)
        draft.updateImage { $0.setPlacement(.leftOfText) }
        #expect(WatermarkEditorPreview(draft: draft, imageData: Data([1])).composition == .imageLeftOfText)
        draft.updateImage { $0.setPlacement(.rightOfText) }
        #expect(WatermarkEditorPreview(draft: draft, imageData: Data([1])).composition == .imageRightOfText)
    }

    @Test func imageOnlyAndDisabledEligibilityAreSafe() {
        let reference = testReference()
        let imageOnly = WatermarkEditorPreview(
            draft: .init(image: .init(enabled: true, assetReference: reference)),
            imageData: Data([1])
        )
        let disabled = WatermarkEditorPreview(
            draft: .init(image: .init(enabled: false, assetReference: reference)),
            imageData: Data([1])
        )

        #expect(imageOnly.composition == .imageOnly)
        #expect(!disabled.hasRenderableImage)
        #expect(disabled.composition == .textOnly)
    }

    @MainActor
    @Test func imageEditsLeaveAllTextLayersUntouchedAndRemovalResetsPreview() async throws {
        let data = try encodedImage(type: .png)
        let imported = try await WatermarkImageImporter().importImage(data: data)
        let importer = StubImageImporter(result: .success(imported))
        let model = WatermarkEditorModel(imageImporter: importer)
        let textLayers = [model.layer(for: .heading), model.layer(for: .body), model.layer(for: .caption)]

        model.importImage(data: data)
        await model.waitForImageImport()
        model.setImageScale(2.4)
        model.setImagePlacement(.rightOfText)
        await model.waitForPreview()

        #expect([model.layer(for: .heading), model.layer(for: .body), model.layer(for: .caption)] == textLayers)
        #expect(model.preview.hasRenderableImage)
        #expect(model.preview.composition == .imageOnly)

        model.removeImage()
        await model.waitForPreview()
        #expect(!model.preview.hasRenderableImage)
        #expect(model.imageImportState == .empty)
    }

    @MainActor
    @Test func importRejectionNeverCreatesAnImageLayer() async {
        let model = WatermarkEditorModel(imageImporter: StubImageImporter(result: .failure(.unsupportedMediaType)))

        model.importImage(data: Data([0x00]))
        await model.waitForImageImport()

        #expect(model.imageImportState == .rejected(.unsupportedMediaType))
        #expect(model.imageLayer().assetReference == nil)
        #expect(!model.preview.hasRenderableImage)
    }

    private func testReference() -> AssetReference {
        AssetReference(
            id: UUID(),
            relativePath: "watermark-assets/test.png",
            sha256Hex: String(repeating: "a", count: 64),
            byteSize: 1,
            mediaType: "image/png"
        )
    }

    private func encodedImage(type: UTType) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw WatermarkImageImportError.undecodable
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw WatermarkImageImportError.undecodable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WatermarkImageImportError.undecodable }
        return data as Data
    }
}

private struct StubImageImporter: WatermarkImageImporting {
    let result: Result<ImportedWatermarkImage, WatermarkImageImportError>

    func importImage(data: Data) async throws -> ImportedWatermarkImage {
        try result.get()
    }
}

extension SHA256.Digest {
    fileprivate var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
