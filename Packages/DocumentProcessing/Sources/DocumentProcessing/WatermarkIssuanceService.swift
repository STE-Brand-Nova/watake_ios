import CryptoKit
import Foundation
import WatakeDomain

public enum WatermarkIssuanceError: Error, Equatable, Sendable {
    case noDocuments
    case missingRecipient
    case missingPurpose
    case invisibleWatermark
    case sourceUnavailable(pageIndex: Int)
    case persistenceFailed
}

public enum WatermarkTemplateResolver {
    public static func mediumDateString(
        from date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public static func resolve(
        _ config: WatermarkConfig,
        recipient: String,
        purpose: String?,
        date: String
    ) throws -> WatermarkConfig {
        guard !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WatermarkIssuanceError.missingRecipient
        }
        if config.usesPurposeToken, purpose?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw WatermarkIssuanceError.missingPurpose
        }
        func layer(_ value: WatermarkTextLayer?) -> WatermarkTextLayer? {
            value.map {
                WatermarkTextLayer(
                    text: $0.text
                        .replacingOccurrences(of: "{recipient}", with: recipient)
                        .replacingOccurrences(of: "{purpose}", with: purpose ?? "")
                        .replacingOccurrences(of: "{date}", with: date),
                    enabled: $0.enabled,
                    fontName: $0.fontName,
                    sizePreset: $0.sizePreset,
                    colorHex: $0.colorHex,
                    rotation: $0.rotation,
                    opacity: $0.opacity
                )
            }
        }
        return WatermarkConfig(
            schemaVersion: config.schemaVersion,
            automatic: false,
            heading: layer(config.heading),
            body: layer(config.body),
            caption: layer(config.caption),
            image: config.image,
            globalPosition: config.globalPosition,
            globalRotation: config.globalRotation,
            globalOpacity: config.globalOpacity,
            layoutMode: config.layoutMode,
            tileSpacingX: config.tileSpacingX,
            tileSpacingY: config.tileSpacingY
        )
    }
}

/// Serializes version assignment and publishes a complete issuance only after
/// every full-resolution page has rendered and passed the asset-store hash
/// check. Failure and cancellation remove every newly staged rendition asset.
public actor WatermarkIssuanceService {
    private let repository: any WatermarkCopyRepository
    private let assetStore: any DocumentAssetStore
    private let compositor: WatermarkPageCompositor
    private let now: @Sendable () -> Date
    private let makeUUID: @Sendable () -> UUID

    public init(
        repository: any WatermarkCopyRepository,
        assetStore: any DocumentAssetStore,
        compositor: WatermarkPageCompositor = WatermarkPageCompositor(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.assetStore = assetStore
        self.compositor = compositor
        self.now = now
        self.makeUUID = makeUUID
    }

    public func createCopies(
        documents: [StoredDocument],
        recipient: WatermarkRecipient,
        purpose: String?,
        templateConfig: WatermarkConfig,
        watermarkImageData: Data? = nil,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> WatermarkIssuance {
        guard !documents.isEmpty else { throw WatermarkIssuanceError.noDocuments }
        try recipient.validate()
        let timestamp = now()
        let resolved = try WatermarkTemplateResolver.resolve(
            templateConfig,
            recipient: recipient.displayName,
            purpose: purpose,
            date: WatermarkTemplateResolver.mediumDateString(from: timestamp)
        )
        guard resolved.hasVisibleLayer else {
            throw WatermarkIssuanceError.invisibleWatermark
        }

        let context = try await IssuanceContext(
            documents: documents,
            recipient: recipient,
            purpose: purpose,
            templateConfig: templateConfig,
            resolvedConfig: resolved,
            timestamp: timestamp,
            issuanceID: makeUUID(),
            priorIssuances: repository.watermarkIssuances()
        )
        return try await stageAndCommit(context, watermarkImageData: watermarkImageData, progress: progress)
    }

    private func stageAndCommit(
        _ context: IssuanceContext,
        watermarkImageData: Data?,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> WatermarkIssuance {
        var staged: [AssetReference] = []
        var renditions: [WatermarkRendition] = []
        var completedPages = 0
        var allocatedVersions = startingVersions(for: context)
        do {
            let preparedImage = try await prepareWatermarkImage(
                config: context.resolvedConfig,
                providedData: watermarkImageData
            )
            if let stagedReference = preparedImage.stagedReference {
                staged.append(stagedReference)
            }
            for document in context.documents {
                let version = (allocatedVersions[document.id] ?? 0) + 1
                let result = try await renderRendition(
                    document: document,
                    context: context,
                    imageData: preparedImage.data,
                    version: version,
                    progress: RenditionProgress(completedOffset: completedPages, handler: progress)
                )
                staged.append(contentsOf: result.assets)
                renditions.append(result.rendition)
                allocatedVersions[document.id] = version
                completedPages += result.rendition.pages.count
            }
            let issuance = WatermarkIssuance(
                id: context.issuanceID,
                recipientId: context.recipient.id,
                recipientNameSnapshot: context.recipient.displayName,
                purpose: context.purpose?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                templateConfig: context.templateConfig,
                renditions: renditions,
                createdAt: context.timestamp
            )
            try issuance.validate()
            return try await repository.commitWatermarkIssuance(issuance, recipient: context.recipient)
        } catch {
            for reference in staged.reversed() {
                try? await assetStore.removeAsset(reference)
            }
            throw error
        }
    }

    private func prepareWatermarkImage(
        config: WatermarkConfig,
        providedData: Data?
    ) async throws -> (data: Data?, stagedReference: AssetReference?) {
        guard let image = config.image, image.enabled else { return (nil, nil) }
        if let providedData, try await !assetStore.containsAsset(image.assetRef) {
            try await assetStore.saveAsset(providedData, reference: image.assetRef)
            return (providedData, image.assetRef)
        }
        if let providedData {
            return (providedData, nil)
        }
        return try await (assetStore.readAsset(image.assetRef), nil)
    }

    private func renderRendition(
        document: StoredDocument,
        context: IssuanceContext,
        imageData: Data?,
        version: Int,
        progress: RenditionProgress
    ) async throws -> RenditionRenderResult {
        try Task.checkCancellation()
        let renditionID = makeUUID()
        var pages: [RenditionPage] = []
        var assets: [AssetReference] = []
        do {
            for page in document.pages.sorted(by: { $0.index < $1.index }) {
                try Task.checkCancellation()
                let source = try await sourceData(for: page)
                let rendered = try await compositor.renderJPEG(
                    sourceData: source,
                    config: context.resolvedConfig,
                    imageData: imageData
                )
                let reference = makeAssetReference(data: rendered, renditionID: renditionID, pageID: page.id)
                try await assetStore.saveAsset(rendered, reference: reference)
                assets.append(reference)
                pages.append(RenditionPage(id: makeUUID(), pageId: page.id, index: page.index, watermarked: reference))
                progress.handler(progress.completedOffset + pages.count, context.totalPages)
            }
        } catch {
            for reference in assets.reversed() {
                try? await assetStore.removeAsset(reference)
            }
            throw error
        }
        let rendition = WatermarkRendition(
            id: renditionID,
            documentId: document.id,
            issuanceId: context.issuanceID,
            originalNameSnapshot: document.name,
            version: version,
            config: context.resolvedConfig,
            pages: pages,
            createdAt: context.timestamp
        )
        return RenditionRenderResult(rendition: rendition, assets: assets)
    }

    private func sourceData(for page: DocumentPage) async throws -> Data {
        do {
            return try await assetStore.readAsset(page.rectified ?? page.source)
        } catch {
            throw WatermarkIssuanceError.sourceUnavailable(pageIndex: page.index)
        }
    }

    private func startingVersions(for context: IssuanceContext) -> [UUID: Int] {
        context.priorIssuances
            .filter { $0.recipientId == context.recipient.id }
            .flatMap(\.renditions)
            .reduce(into: [:]) { versions, rendition in
                versions[rendition.documentId] = max(versions[rendition.documentId] ?? 0, rendition.version)
            }
    }

    private func makeAssetReference(data: Data, renditionID: UUID, pageID: UUID) -> AssetReference {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return AssetReference(
            id: makeUUID(),
            relativePath: "renditions/\(renditionID.uuidString.lowercased())/pages/\(pageID.uuidString.lowercased()).jpg",
            sha256Hex: digest,
            byteSize: data.count,
            mediaType: "image/jpeg"
        )
    }
}

private struct IssuanceContext: Sendable {
    let documents: [StoredDocument]
    let recipient: WatermarkRecipient
    let purpose: String?
    let templateConfig: WatermarkConfig
    let resolvedConfig: WatermarkConfig
    let timestamp: Date
    let issuanceID: UUID
    let priorIssuances: [WatermarkIssuance]

    var totalPages: Int {
        documents.reduce(0) { $0 + $1.pages.count }
    }
}

private struct RenditionRenderResult: Sendable {
    let rendition: WatermarkRendition
    let assets: [AssetReference]
}

private struct RenditionProgress: Sendable {
    let completedOffset: Int
    let handler: @Sendable (Int, Int) -> Void
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
