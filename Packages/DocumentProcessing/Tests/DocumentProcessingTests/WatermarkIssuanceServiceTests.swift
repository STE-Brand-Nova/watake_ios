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
