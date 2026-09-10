import Foundation
import ImageIO
import Testing
import WatakeDomain
@testable import DocumentProcessing

@Suite("Recipient watermark issuance")
struct WatermarkIssuanceServiceTests {
    @Test func multipageIssuancePersistsOrderedPagesAndIncrementsRecipientVersion() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(180, 240), (240, 180)])
        await TestDocumentFactory.seedAssets(document: fixture.document, data: fixture.pageData, into: fixture.store)
        let repository = MemoryCopyRepository()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let recipient = WatermarkRecipient(id: UUID(), displayName: "Acme", createdAt: date, updatedAt: date)
        let service = WatermarkIssuanceService(repository: repository, assetStore: fixture.store, now: { date })

        let first = try await service.createCopies(
            documents: [fixture.document],
            recipient: recipient,
            purpose: "Hiring",
            templateConfig: templateConfig()
        )
        let second = try await service.createCopies(
            documents: [fixture.document],
            recipient: recipient,
            purpose: "Hiring",
            templateConfig: templateConfig()
        )

        #expect(first.renditions.count == 1)
        #expect(first.renditions[0].pages.map(\.index) == [0, 1])
        #expect(first.renditions[0].version == 1)
        #expect(second.renditions[0].version == 2)
        #expect(first.templateConfig.body?.text.contains("{recipient}") == true)
        #expect(first.renditions[0].config.body?.text.contains("Acme") == true)
        #expect(first.renditions[0].config.body?.text.contains("Hiring") == true)
        #expect(await repository.issuanceCount() == 2)
    }

    @Test func existingSnapshotKeepsOldOrderWhileNewCopyUsesCurrentOrder() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(180, 240), (240, 180)])
        await TestDocumentFactory.seedAssets(document: fixture.document, data: fixture.pageData, into: fixture.store)
        let repository = MemoryCopyRepository()
        let recipient = WatermarkRecipient(id: UUID(), displayName: "Acme", createdAt: .now, updatedAt: .now)
        let service = WatermarkIssuanceService(repository: repository, assetStore: fixture.store)

        let historical = try await service.createCopies(
            documents: [fixture.document],
            recipient: recipient,
            purpose: "Initial",
            templateConfig: templateConfig()
        )
        let sourceOrdered = fixture.document.pages.sorted { $0.index < $1.index }
        let reorderedPages = [sourceOrdered[1], sourceOrdered[0]].enumerated().map { index, page in
            DocumentPage(
                id: page.id,
                index: index,
                originalIndex: page.originalIndex,
                source: page.source,
                rectified: page.rectified,
                ocrText: page.ocrText,
                ocrBlocks: page.ocrBlocks
            )
        }
        let current = StoredDocument(
            id: fixture.document.id,
            folderId: fixture.document.folderId,
            name: fixture.document.name,
            createdAt: fixture.document.createdAt,
            updatedAt: .now,
            orderIndex: fixture.document.orderIndex,
            pages: reorderedPages
        )

        let newCopy = try await service.createCopies(
            documents: [current],
            recipient: recipient,
            purpose: "Updated",
            templateConfig: templateConfig()
        )

        #expect(historical.renditions[0].pages.map(\.pageId) == sourceOrdered.map(\.id))
        #expect(newCopy.renditions[0].pages.map(\.pageId) == reorderedPages.map(\.id))
    }

    @Test func failedCommitRemovesEveryStagedRenditionAsset() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(120, 160), (120, 160)])
        await TestDocumentFactory.seedAssets(document: fixture.document, data: fixture.pageData, into: fixture.store)
        let originalPaths = await fixture.store.allPaths()
        let repository = MemoryCopyRepository(failIssuanceSave: true)
        let recipient = WatermarkRecipient(id: UUID(), displayName: "Acme", createdAt: .now, updatedAt: .now)
        let service = WatermarkIssuanceService(repository: repository, assetStore: fixture.store)

        await #expect(throws: CopyRepositoryFailure.self) {
            _ = try await service.createCopies(
                documents: [fixture.document],
                recipient: recipient,
                purpose: "Hiring",
                templateConfig: templateConfig()
            )
        }

        #expect(await fixture.store.allPaths() == originalPaths)
        #expect(await repository.issuanceCount() == 0)
    }

    @Test func cancellationMidBatchRemovesEveryStagedRenditionAsset() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(120, 160), (120, 160), (120, 160)])
        await TestDocumentFactory.seedAssets(document: fixture.document, data: fixture.pageData, into: fixture.store)
        let originalPaths = await fixture.store.allPaths()
        let signalingStore = SignalingAssetStore(inner: fixture.store)
        let repository = MemoryCopyRepository()
        let recipient = WatermarkRecipient(id: UUID(), displayName: "Acme", createdAt: .now, updatedAt: .now)
        let service = WatermarkIssuanceService(repository: repository, assetStore: signalingStore)

        let creation = Task {
            try await service.createCopies(
                documents: [fixture.document],
                recipient: recipient,
                purpose: "Hiring",
                templateConfig: templateConfig()
            )
        }
        await signalingStore.firstReadStarted
        creation.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await creation.value
        }
        #expect(await fixture.store.allPaths() == originalPaths)
        #expect(await repository.issuanceCount() == 0)
    }

    @Test func duplicateDocumentInputReceivesDistinctVersionsWithinOneIssuance() async throws {
        let fixture = TestDocumentFactory.makeDocument(pageSizes: [(120, 160)])
        await TestDocumentFactory.seedAssets(document: fixture.document, data: fixture.pageData, into: fixture.store)
        let recipient = WatermarkRecipient(id: UUID(), displayName: "Acme", createdAt: .now, updatedAt: .now)
        let service = WatermarkIssuanceService(repository: MemoryCopyRepository(), assetStore: fixture.store)

        let issuance = try await service.createCopies(
            documents: [fixture.document, fixture.document],
            recipient: recipient,
            purpose: "Hiring",
            templateConfig: templateConfig()
        )

        #expect(issuance.renditions.map(\.version) == [1, 2])
    }

    @Test func templateDateUsesExplicitLocaleAndPurposeValidationIsShared() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let formatted = WatermarkTemplateResolver.mediumDateString(
            from: date,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: utc
        )
        #expect(formatted == "Nov 14, 2023")
        #expect(templateConfig().usesPurposeToken)
        #expect(throws: WatermarkIssuanceError.missingPurpose) {
            _ = try WatermarkTemplateResolver.resolve(
                templateConfig(),
                recipient: "Acme",
                purpose: nil,
                date: formatted
            )
        }
    }

    @Test func malformedColorFailsInsteadOfRenderingBlack() async {
        let source = SyntheticImage.makePNGData(width: 120, height: 160, red: 1, green: 1, blue: 1)
        let config = WatermarkConfig(
            automatic: false,
            body: WatermarkTextLayer(
                text: "CONFIDENTIAL", enabled: true, fontName: "Helvetica", sizePreset: .medium,
                colorHex: "not-a-color", rotation: 0, opacity: 1
            ),
            globalPosition: .center,
            globalRotation: 0,
            globalOpacity: 1
        )

        await #expect(throws: DomainValidationError.invalidColorHex("not-a-color")) {
            _ = try await WatermarkPageCompositor().renderJPEG(sourceData: source, config: config)
        }
    }

    @Test func previewAndOutputUseTheSameCompositorAndNormalizeOrientation() async throws {
        let source = SyntheticImage.makePNGData(width: 240, height: 120, red: 1, green: 1, blue: 1)
        let compositor = WatermarkPageCompositor()
        let config = templateConfig(layoutMode: .tiled)

        let preview = try await compositor.renderJPEG(
            sourceData: source,
            config: config,
            maximumPixelDimension: 120,
            quality: 0.9
        )
        let output = try await compositor.renderJPEG(sourceData: source, config: config)

        let previewSize = try #require(imageSize(preview))
        let outputSize = try #require(imageSize(output))
        #expect(previewSize.0 == 120)
        #expect(previewSize.1 == 60)
        #expect(outputSize.0 == 240)
        #expect(outputSize.1 == 120)
    }

    @Test func positiveImageLayerRotationIsClockwiseLikeSwiftUIPreview() async throws {
        let source = SyntheticImage.makePNGData(width: 300, height: 300, red: 1, green: 1, blue: 1)
        let marker = SyntheticImage.makeTopBottomPNGData(
            width: 40,
            height: 80,
            topColor: SyntheticColor(red: 1, green: 0, blue: 0),
            bottomColor: SyntheticColor(red: 0, green: 0, blue: 1)
        )
        let reference = SyntheticImage.makeAssetReference(pageId: UUID(), data: marker)
        let config = WatermarkConfig(
            automatic: false,
            image: WatermarkImageLayer(
                enabled: true,
                assetRef: reference,
                scale: 1,
                rotation: 90,
                opacity: 1,
                placement: .aboveText
            ),
            globalPosition: .center,
            globalRotation: 0,
            globalOpacity: 1
        )

        let result = try await WatermarkPageCompositor().renderJPEG(
            sourceData: source,
            config: config,
            imageData: marker,
            quality: 1
        )
        let rendered = try #require(CGImageSourceCreateWithData(result as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(rendered, 0, nil))
        let left = try sampledPixel(in: image, column: 130, row: 150)
        let right = try sampledPixel(in: image, column: 170, row: 150)

        #expect(left.blue > 0.75)
        #expect(left.red < 0.25)
        #expect(right.red > 0.75)
        #expect(right.blue < 0.25)
    }

    private func templateConfig(layoutMode: WatermarkLayoutMode = .single) -> WatermarkConfig {
        WatermarkConfig(
            automatic: false,
            heading: WatermarkTextLayer(
                text: "CONFIDENTIAL", enabled: true, fontName: "Helvetica-Bold", sizePreset: .large,
                colorHex: "#0B1220", rotation: -4, opacity: 0.7
            ),
            body: WatermarkTextLayer(
                text: "For {recipient}\n{purpose} · {date}", enabled: true, fontName: "Helvetica", sizePreset: .medium,
                colorHex: "#0B1220", rotation: 0, opacity: 0.65
            ),
            caption: WatermarkTextLayer(
                text: "Do not redistribute", enabled: true, fontName: "Helvetica", sizePreset: .small,
                colorHex: "#0B1220", rotation: 2, opacity: 0.55
            ),
            globalPosition: .center,
            globalRotation: 12,
            globalOpacity: 0.8,
            layoutMode: layoutMode,
            tileSpacingX: layoutMode == .tiled ? 0.32 : nil,
            tileSpacingY: layoutMode == .tiled ? 0.28 : nil
        )
    }

    private func imageSize(_ data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        return (width, height)
    }

    private func sampledPixel(in image: CGImage, column: Int, row: Int) throws -> (red: Double, blue: Double) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .none
        context.translateBy(x: CGFloat(-column), y: CGFloat(-(image.height - row - 1)))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (Double(bytes[0]) / 255, Double(bytes[2]) / 255)
    }
}

private enum CopyRepositoryFailure: Error { case failed }

private actor MemoryCopyRepository: WatermarkCopyRepository {
    private var recipients: [WatermarkRecipient] = []
    private var issuances: [WatermarkIssuance] = []
    private let failIssuanceSave: Bool

    init(failIssuanceSave: Bool = false) {
        self.failIssuanceSave = failIssuanceSave
    }

    func watermarkRecipients() async throws -> [WatermarkRecipient] {
        recipients
    }

    func saveWatermarkRecipient(_ recipient: WatermarkRecipient) async throws {
        recipients.removeAll { $0.id == recipient.id }
        recipients.append(recipient)
    }

    func watermarkIssuances() async throws -> [WatermarkIssuance] {
        issuances
    }

    func saveWatermarkIssuance(_ issuance: WatermarkIssuance) async throws {
        if failIssuanceSave {
            throw CopyRepositoryFailure.failed
        }
        issuances.removeAll { $0.id == issuance.id }
        issuances.append(issuance)
    }

    func commitWatermarkIssuance(
        _ issuance: WatermarkIssuance,
        recipient: WatermarkRecipient
    ) async throws -> WatermarkIssuance {
        if failIssuanceSave {
            throw CopyRepositoryFailure.failed
        }
        try await saveWatermarkRecipient(recipient)
        try await saveWatermarkIssuance(issuance)
        return issuance
    }

    func removeWatermarkIssuance(id: UUID) async throws {
        issuances.removeAll { $0.id == id }
    }

    func issuanceCount() -> Int {
        issuances.count
    }
}
