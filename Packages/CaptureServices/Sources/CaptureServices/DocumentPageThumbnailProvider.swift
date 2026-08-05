#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    import Foundation
    import WatakeDomain

    /// Domain-facing thumbnail port backed by the existing disk `ThumbnailCache`
    /// (the same cache `LibraryStore.thumbnailData(for:)` already uses for
    /// folder-list thumbnails). Prefers the rectified derivative and falls back
    /// to the immutable source on a missing/corrupt rectified asset, mirroring
    /// `DocumentViewerModel`'s main-preview fallback. Never loads a full-size
    /// asset merely to serve a cache hit.
    public actor DocumentPageThumbnailProvider: DocumentPageThumbnailLoading {
        private let assetStore: any DocumentAssetStore
        private let cache: ThumbnailCache
        private let maxPixelSize: Int

        public init(assetStore: any DocumentAssetStore, cache: ThumbnailCache, maxPixelSize: Int = 112) {
            self.assetStore = assetStore
            self.cache = cache
            self.maxPixelSize = maxPixelSize
        }

        public func thumbnail(for page: DocumentPage) async throws -> Data {
            if let rectified = page.rectified {
                if let cached = await cache.cachedThumbnailIfPresent(for: rectified, maxPixelSize: maxPixelSize) {
                    return cached
                }
                do {
                    let data = try await assetStore.readAsset(rectified)
                    return try await cache.thumbnail(for: rectified, data: data, maxPixelSize: maxPixelSize)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Rectified asset missing/corrupt: fall through to the source.
                }
            }
            if let cached = await cache.cachedThumbnailIfPresent(for: page.source, maxPixelSize: maxPixelSize) {
                return cached
            }
            let data = try await assetStore.readAsset(page.source)
            return try await cache.thumbnail(for: page.source, data: data, maxPixelSize: maxPixelSize)
        }
    }
#endif
