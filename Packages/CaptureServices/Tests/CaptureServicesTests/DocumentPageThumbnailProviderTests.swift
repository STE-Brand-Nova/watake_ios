import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import WatakeDomain
@testable import CaptureServices

@Suite("DocumentPageThumbnailProvider")
struct DocumentPageThumbnailProviderTests {
    @Test("a cache hit never reads the full-resolution asset")
    func cacheHitAvoidsAssetRead() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ThumbnailCache(directory: directory)
        let image = try makeImageData(width: 40, height: 40)
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)

        // Pre-populate the cache directly so the provider should never touch the asset store.
        _ = try await cache.thumbnail(for: source, data: image, maxPixelSize: 64)

        let assetStore = FakeThumbnailAssetStore()
        let provider = DocumentPageThumbnailProvider(assetStore: assetStore, cache: cache, maxPixelSize: 64)

        let thumbnail = try await provider.thumbnail(for: page)
        #expect(!thumbnail.isEmpty)
        #expect(await assetStore.readCount == 0)
    }

    @Test("a cache miss reads the asset once and generates a smaller thumbnail")
    func cacheMissGeneratesThumbnail() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ThumbnailCache(directory: directory)
        let image = try makeImageData(width: 800, height: 800)
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)

        let assetStore = FakeThumbnailAssetStore()
        await assetStore.setAsset(image, for: source)
        let provider = DocumentPageThumbnailProvider(assetStore: assetStore, cache: cache, maxPixelSize: 64)

        let thumbnail = try await provider.thumbnail(for: page)
        #expect(thumbnail.count < image.count)
        #expect(await assetStore.readCount == 1)

        // A second request must now hit the disk cache, not read the asset again.
        _ = try await provider.thumbnail(for: page)
        #expect(await assetStore.readCount == 1)
    }

    @Test("a corrupt cached thumbnail self-heals: it's discarded and regenerated from the asset")
    func corruptCacheEntryFallsBackToRegeneration() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ThumbnailCache(directory: directory)
        let source = makeAssetReference()
        let page = makePage(index: 0, source: source)

        // Simulate a corrupted cache entry written by an interrupted prior run.
        let corruptURL = directory.appendingPathComponent("\(source.sha256Hex)-64.jpg")
        try Data("not a real image".utf8).write(to: corruptURL)

        let image = try makeImageData(width: 40, height: 40)
        let assetStore = FakeThumbnailAssetStore()
        await assetStore.setAsset(image, for: source)
        let provider = DocumentPageThumbnailProvider(assetStore: assetStore, cache: cache, maxPixelSize: 64)

        let thumbnail = try await provider.thumbnail(for: page)
        #expect(CGImageSourceCreateWithData(thumbnail as CFData, nil) != nil)
        #expect(await assetStore.readCount == 1)
    }

    @Test("a missing or corrupt rectified asset falls back to the immutable source")
    func rectifiedFailureFallsBackToSource() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ThumbnailCache(directory: directory)
        let sourceImage = try makeImageData(width: 40, height: 40)
        let source = makeAssetReference()
        let rectified = makeAssetReference()
        let page = makePage(index: 0, source: source, rectified: rectified)

        let assetStore = FakeThumbnailAssetStore()
        await assetStore.setAsset(sourceImage, for: source)
        await assetStore.setError(TestFixtureError.missing, for: rectified)
        let provider = DocumentPageThumbnailProvider(assetStore: assetStore, cache: cache, maxPixelSize: 64)

        let thumbnail = try await provider.thumbnail(for: page)
        #expect(CGImageSourceCreateWithData(thumbnail as CFData, nil) != nil)
    }
}

private enum TestFixtureError: Error, Equatable, Sendable { case missing }

private actor FakeThumbnailAssetStore: DocumentAssetStore {
    private var dataByAssetID: [UUID: Data] = [:]
    private var errorsByAssetID: [UUID: Error] = [:]
    private(set) var readCount = 0

    func setAsset(_ data: Data, for reference: AssetReference) {
        dataByAssetID[reference.id] = data
    }

    func setError(_ error: Error, for reference: AssetReference) {
        errorsByAssetID[reference.id] = error
    }

    func saveAsset(_ data: Data, reference: AssetReference) async throws {
        dataByAssetID[reference.id] = data
    }

    func readAsset(_ reference: AssetReference) async throws -> Data {
        readCount += 1
        if let error = errorsByAssetID[reference.id] {
            throw error
        }
        guard let data = dataByAssetID[reference.id] else {
            throw TestFixtureError.missing
        }
        return data
    }

    func containsAsset(_ reference: AssetReference) async throws -> Bool {
        dataByAssetID[reference.id] != nil
    }

    func removeAsset(_ reference: AssetReference) async throws {
        dataByAssetID[reference.id] = nil
    }
}

private func makeAssetReference(id: UUID = UUID(), path: String = "page.bin") -> AssetReference {
    let digest = id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    return AssetReference(
        id: id,
        relativePath: path,
        sha256Hex: digest + String(repeating: "0", count: 64 - digest.count),
        byteSize: 1,
        mediaType: "application/octet-stream"
    )
}

private func makePage(id: UUID = UUID(), index: Int, source: AssetReference, rectified: AssetReference? = nil) -> DocumentPage {
    DocumentPage(id: id, index: index, source: source, rectified: rectified)
}

private func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
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
