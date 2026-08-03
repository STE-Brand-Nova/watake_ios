import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import WatakeDomain
@testable import DocumentViewerFeature

@Suite("DocumentPageThumbnailLoader")
struct DocumentPageThumbnailLoaderTests {
    @Test("downsamples the source image well below its original byte size")
    func downsamplesImage() async throws {
        let original = try makeImageData(width: 800, height: 800)
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)

        let loader = FakeLoader()
        await loader.setAsset(original, for: source)

        let thumbnailLoader = DocumentPageThumbnailLoader(loader: loader)
        let thumbnail = try await thumbnailLoader.thumbnail(for: page)

        #expect(thumbnail.count < original.count)
    }

    @Test("a corrupt or missing rectified asset falls back to the immutable source")
    func fallsBackToSourceOnRectifiedFailure() async throws {
        let sourceData = try makeImageData(width: 40, height: 40)
        let source = makeAssetReference()
        let rectified = makeAssetReference()
        let page = makePage(index: 0, source: source, rectified: rectified)

        let loader = FakeLoader()
        await loader.setAssetError(FakeLoaderError.assetUnreadable, for: rectified)
        await loader.setAsset(sourceData, for: source)

        let thumbnailLoader = DocumentPageThumbnailLoader(loader: loader)
        let thumbnail = try await thumbnailLoader.thumbnail(for: page)

        #expect(!thumbnail.isEmpty)
    }

    @Test("caches a page's thumbnail so repeated requests don't re-read the asset")
    func cachesThumbnail() async throws {
        let data = try makeImageData(width: 40, height: 40)
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)

        let loader = FakeLoader()
        await loader.setAsset(data, for: source)

        let thumbnailLoader = DocumentPageThumbnailLoader(loader: loader)
        _ = try await thumbnailLoader.thumbnail(for: page)
        _ = try await thumbnailLoader.thumbnail(for: page)

        #expect(await loader.readAssetCallCount == 1)
    }

    @Test("bounds concurrent full-asset reads across many pages")
    func boundsConcurrentLoads() async throws {
        let data = try makeImageData(width: 40, height: 40)
        let loader = ConcurrencyTrackingLoader(imageData: data)
        let thumbnailLoader = DocumentPageThumbnailLoader(loader: loader, maxConcurrentLoads: 2)
        let pages = (0 ..< 8).map { makePage(index: $0, source: makeAssetReference()) }

        await withTaskGroup(of: Void.self) { group in
            for page in pages {
                group.addTask { _ = try? await thumbnailLoader.thumbnail(for: page) }
            }
        }

        #expect(await loader.maxObservedConcurrent <= 2)
    }
}

private actor ConcurrencyTrackingLoader: DocumentPageAssetLoading {
    private let imageData: Data
    private var current = 0
    private(set) var maxObservedConcurrent = 0

    init(imageData: Data) {
        self.imageData = imageData
    }

    func document(id: UUID) async throws -> StoredDocument? {
        nil
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        current += 1
        maxObservedConcurrent = max(maxObservedConcurrent, current)
        try await Task.sleep(nanoseconds: 30_000_000)
        current -= 1
        return imageData
    }
}

private func makeImageData(width: Int, height: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let cgImage = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, cgImage, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}
