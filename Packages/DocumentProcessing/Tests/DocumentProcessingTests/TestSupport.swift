import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WatakeDomain
@testable import DocumentProcessing

/// In-memory `DocumentAssetStore` double. Never touches disk; keyed by
/// `relativePath` like the real store's on-disk layout.
actor InMemoryAssetStore: DocumentAssetStore {
    private var storage: [String: Data] = [:]

    func seed(_ data: Data, reference: AssetReference) {
        storage[reference.relativePath] = data
    }

    func saveAsset(_ data: Data, reference: AssetReference) async throws {
        storage[reference.relativePath] = data
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        guard let data = storage[reference.relativePath] else {
            throw TestAssetStoreError.missing
        }
        return data
    }

    func containsAsset(_ reference: AssetReference) async throws -> Bool {
        storage[reference.relativePath] != nil
    }

    func removeAsset(_ reference: AssetReference) async throws {
        storage.removeValue(forKey: reference.relativePath)
    }
}

enum TestAssetStoreError: Error {
    case missing
}

/// Wraps `InMemoryAssetStore` and signals once via `firstReadStarted` after
/// the first `readAsset` call begins, so tests can synchronize a cancellation
/// to a point strictly after rendering has started reading page data.
actor SignalingAssetStore: DocumentAssetStore {
    private let inner: InMemoryAssetStore
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasSignaled = false

    init(inner: InMemoryAssetStore) {
        self.inner = inner
    }

    var firstReadStarted: Void {
        get async {
            if hasSignaled {
                return
            }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    func saveAsset(_ data: Data, reference: AssetReference) async throws {
        try await inner.saveAsset(data, reference: reference)
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        signalFirstRead()
        return try await inner.readAsset(reference)
    }

    func containsAsset(_ reference: AssetReference) async throws -> Bool {
        try await inner.containsAsset(reference)
    }

    func removeAsset(_ reference: AssetReference) async throws {
        try await inner.removeAsset(reference)
    }

    private func signalFirstRead() {
        guard !hasSignaled else {
            return
        }
        hasSignaled = true
        continuation?.resume()
        continuation = nil
    }
}

struct SyntheticColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

enum SyntheticImage {
    /// Renders a solid-color PNG of the given pixel size, useful as a
    /// deterministic, non-personal stand-in for a captured document page.
    static func makePNGData(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Failed to create test bitmap context")
        }
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            fatalError("Failed to create test image")
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Failed to create test image destination")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Failed to finalize test image")
        }
        return data as Data
    }

    /// Renders a PNG whose top half is `topColor` and bottom half is
    /// `bottomColor`, in image (top-down) row order, so tests can detect an
    /// accidental vertical flip between source image and rendered PDF page.
    static func makeTopBottomPNGData(
        width: Int,
        height: Int,
        topColor: SyntheticColor,
        bottomColor: SyntheticColor
    ) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Failed to create test bitmap context")
        }
        let halfHeight = height / 2
        // CGContext origin is bottom-left, so the "top" half of the image
        // (as PNG rows are read top-down) is drawn at the top of this rect.
        context.setFillColor(red: topColor.red, green: topColor.green, blue: topColor.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: height - halfHeight, width: width, height: halfHeight))
        context.setFillColor(red: bottomColor.red, green: bottomColor.green, blue: bottomColor.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height - halfHeight))
        guard let cgImage = context.makeImage() else {
            fatalError("Failed to create test image")
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Failed to create test image destination")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Failed to finalize test image")
        }
        return data as Data
    }

    static func makeAssetReference(pageId: UUID, data: Data) -> AssetReference {
        AssetReference(
            id: pageId,
            relativePath: "documents/test/source/\(pageId.uuidString.lowercased()).png",
            sha256Hex: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            byteSize: data.count,
            mediaType: "image/png"
        )
    }
}

struct TestDocumentFixture {
    let document: StoredDocument
    let store: InMemoryAssetStore
    let pageData: [Data]
}

enum TestDocumentFactory {
    static func makeDocument(pageSizes: [(width: Int, height: Int)]) -> TestDocumentFixture {
        let store = InMemoryAssetStore()
        var pages: [DocumentPage] = []
        var pageDataList: [Data] = []

        for (offset, size) in pageSizes.enumerated() {
            let pageId = UUID()
            let data = SyntheticImage.makePNGData(
                width: size.width,
                height: size.height,
                red: CGFloat(offset) / CGFloat(max(pageSizes.count, 1)),
                green: 0.4,
                blue: 0.6
            )
            let reference = SyntheticImage.makeAssetReference(pageId: pageId, data: data)
            pages.append(DocumentPage(id: pageId, index: offset, source: reference))
            pageDataList.append(data)
        }

        let document = StoredDocument(
            id: UUID(),
            folderId: UUID(),
            name: "Synthetic",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            orderIndex: 0,
            pages: pages
        )

        return TestDocumentFixture(document: document, store: store, pageData: pageDataList)
    }

    static func seedAssets(document: StoredDocument, data: [Data], into store: InMemoryAssetStore) async {
        for (page, pageData) in zip(document.pages, data) {
            await store.seed(pageData, reference: page.source)
        }
    }
}

func makeTextLayer(
    text: String = "Confidential",
    enabled: Bool = true,
    fontName: String = "Helvetica",
    sizePreset: WatermarkSizePreset = .medium,
    colorHex: String = "#FF0000",
    rotation: Double = 0,
    opacity: Double = 1
) -> WatermarkTextLayer {
    WatermarkTextLayer(
        text: text,
        enabled: enabled,
        fontName: fontName,
        sizePreset: sizePreset,
        colorHex: colorHex,
        rotation: rotation,
        opacity: opacity
    )
}

func makeConfig(
    body: WatermarkTextLayer? = makeTextLayer(),
    heading: WatermarkTextLayer? = nil,
    caption: WatermarkTextLayer? = nil,
    image: WatermarkImageLayer? = nil,
    globalPosition: WatermarkPosition = .center,
    globalRotation: Double = 0,
    globalOpacity: Double = 1,
    layoutMode: WatermarkLayoutMode = .single,
    tileSpacingX: Double? = nil,
    tileSpacingY: Double? = nil
) -> WatermarkConfig {
    WatermarkConfig(
        automatic: false,
        heading: heading,
        body: body,
        caption: caption,
        image: image,
        globalPosition: globalPosition,
        globalRotation: globalRotation,
        globalOpacity: globalOpacity,
        layoutMode: layoutMode,
        tileSpacingX: tileSpacingX,
        tileSpacingY: tileSpacingY
    )
}
