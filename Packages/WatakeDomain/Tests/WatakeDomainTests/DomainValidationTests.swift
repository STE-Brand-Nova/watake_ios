import Foundation
import Testing
@testable import WatakeDomain

@Suite("Domain validation")
struct DomainValidationTests {
    @Test("folder rejects whitespace-only names")
    func folderRejectsWhitespaceOnlyName() {
        let folder = Folder(id: UUID(), name: " \n\t ", colorHex: "#3B82F6", createdAt: .now)

        expectValidationError(.emptyName(field: "name")) {
            try folder.validate()
        }
    }

    @Test("document requires at least one page")
    func documentRequiresPage() {
        let document = makeDocument(pages: [])

        expectValidationError(.documentRequiresPage) {
            try document.validate()
        }
    }

    @Test("page indexes must be zero-based and contiguous")
    func pageIndexesMustBeContiguous() {
        let document = makeDocument(pages: [
            makePage(index: 0),
            makePage(index: 2)
        ])

        expectValidationError(.pageIndexesNotContiguous) {
            try document.validate()
        }
    }

    @Test("page indexes must be unique")
    func pageIndexesMustBeUnique() {
        let document = makeDocument(pages: [
            makePage(index: 0),
            makePage(index: 0)
        ])

        expectValidationError(.pageIndexesNotContiguous) {
            try document.validate()
        }
    }

    @Test("asset path must be relative")
    func assetPathMustBeRelative() {
        let reference = makeAsset(relativePath: "/folders/document/original.jpg")

        expectValidationError(.invalidAssetPath(reference.relativePath)) {
            try reference.validate()
        }
    }

    @Test("asset path must be normalized")
    func assetPathMustBeNormalized() {
        let reference = makeAsset(relativePath: "folders//document/original.jpg")

        expectValidationError(.invalidAssetPath(reference.relativePath)) {
            try reference.validate()
        }
    }

    @Test("asset path cannot contain parent traversal")
    func assetPathCannotContainParentTraversal() {
        let reference = makeAsset(relativePath: "folders/../document/original.jpg")

        expectValidationError(.invalidAssetPath(reference.relativePath)) {
            try reference.validate()
        }
    }

    @Test("sha256 must be lowercase 64-character hex")
    func sha256MustBeLowercaseHex() {
        let reference = makeAsset(sha256Hex: String(repeating: "A", count: 64))

        expectValidationError(.invalidSHA256(reference.sha256Hex)) {
            try reference.validate()
        }
    }

    @Test("ocr bounds must stay inside unit square")
    func ocrBoundsMustStayInsideUnitSquare() {
        let block = OCRBlock(
            id: fixedUUID(10),
            text: "synthetic text",
            bounds: NormalizedRect(originX: 0.8, originY: 0.8, width: 0.3, height: 0.1)
        )

        expectValidationError(.ocrBoundsOutsideUnitSquare) {
            try block.validate()
        }
    }

    @Test("opacity must be between zero and one")
    func opacityMustBeBetweenZeroAndOne() {
        let layer = makeTextLayer(opacity: 1.1)

        expectValidationError(.opacityOutOfRange(1.1)) {
            try layer.validate()
        }
    }

    @Test("rotation must be within negative and positive 180 degrees")
    func rotationMustBeInRange() {
        let config = makeWatermarkConfig(globalRotation: 181)

        expectValidationError(.rotationOutOfRange(181)) {
            try config.validate()
        }
    }

    @Test("export draft page IDs must be unique")
    func exportDraftPageIDsMustBeUnique() {
        let pageId = fixedUUID(20)
        let draft = ExportDraft(id: fixedUUID(21), documentId: fixedUUID(22), pageIds: [pageId, pageId], format: .pdf, createdAt: fixedDate)

        expectValidationError(.duplicateExportDraftPageIDs) {
            try draft.validate()
        }
    }

    @Test("stored document order index must be non-negative")
    func orderIndexMustBeNonNegative() {
        let document = StoredDocument(
            id: fixedUUID(2),
            folderId: fixedUUID(3),
            name: "Document",
            createdAt: fixedDate,
            updatedAt: fixedDate,
            orderIndex: -1,
            pages: [makePage()]
        )

        expectValidationError(.negativeOrderIndex(-1)) {
            try document.validate()
        }
    }

    @Test("stored document tag IDs must be unique")
    func tagIDsMustBeUnique() {
        let tagId = fixedUUID(5)
        let document = makeDocument(tagIds: [tagId, tagId])

        expectValidationError(.duplicateTagIDs) {
            try document.validate()
        }
    }

    @Test("watermark schema version must be at least one")
    func schemaVersionMustBeAtLeastOne() {
        let config = makeWatermarkConfig(schemaVersion: 0)

        expectValidationError(.invalidSchemaVersion(0)) {
            try config.validate()
        }
    }

    @Test("ocr text normalizes line endings through initializer")
    func ocrTextNormalizesThroughInitializer() {
        let page = makePage(ocrText: "one\r\ntwo\rthree")

        #expect(page.ocrText == "one\ntwo\nthree")
    }

    @Test("OCR result normalizes text and requires matching blocks")
    func OCRResultNormalizesText() throws {
        let block = OCRBlock(
            id: fixedUUID(12),
            text: "synthetic\r\ntext",
            confidence: 0.8,
            bounds: NormalizedRect(originX: 0, originY: 0, width: 0.2, height: 0.2),
            language: "en-US"
        )
        let result = OCRRecognitionResult(text: "synthetic\r\ntext", blocks: [block])

        #expect(result.text == "synthetic\ntext")
        try result.validate()
    }

    @Test("OCR block rejects invalid confidence and empty text")
    func OCRBlockValidation() {
        let invalidConfidence = OCRBlock(
            id: fixedUUID(13),
            text: "synthetic",
            confidence: 1.1,
            bounds: NormalizedRect(originX: 0, originY: 0, width: 0.2, height: 0.2)
        )
        expectValidationError(.ocrConfidenceOutOfRange(1.1)) {
            try invalidConfidence.validate()
        }
        let emptyText = OCRBlock(
            id: fixedUUID(14),
            text: " \n",
            bounds: NormalizedRect(originX: 0, originY: 0, width: 0.2, height: 0.2)
        )
        expectValidationError(.emptyOCRText) {
            try emptyText.validate()
        }
    }

    @Test("key models round-trip through contract Codable")
    func codableRoundTrip() throws {
        let models = KeyModels(
            folder: Folder(id: fixedUUID(30), name: "Inbox", colorHex: "#112233", createdAt: fixedDate),
            document: makeDocument(),
            tag: WatakeDomain.Tag(id: fixedUUID(31), label: "Work", colorHex: "#445566"),
            preset: WatermarkPreset(
                id: fixedUUID(32),
                name: "Company",
                config: makeWatermarkConfig(),
                createdAt: fixedDate,
                updatedAt: fixedDate
            ),
            rendition: WatermarkRendition(
                id: fixedUUID(33),
                documentId: fixedUUID(2),
                config: makeWatermarkConfig(),
                pages: [
                    RenditionPage(
                        id: fixedUUID(34),
                        pageId: fixedUUID(4),
                        index: 0,
                        watermarked: makeAsset(relativePath: "folders/d/w.jpg")
                    )
                ],
                createdAt: fixedDate
            ),
            draft: ExportDraft(id: fixedUUID(35), documentId: fixedUUID(2), pageIds: [fixedUUID(4)], format: .pdf, createdAt: fixedDate)
        )

        let data = try WatakeContractCoding.makeJSONEncoder().encode(models)
        let decoded = try WatakeContractCoding.makeJSONDecoder().decode(KeyModels.self, from: data)

        #expect(decoded == models)
    }

    @Test("contract encoder emits lowercase UUID strings and UTC RFC3339 dates")
    func contractEncoderEmitsUUIDAndDateStrings() throws {
        let folder = Folder(id: uuidWithLetters, name: "Inbox", colorHex: "#112233", createdAt: fixedDate)
        let object = try jsonObject(for: folder)

        #expect(object["id"] as? String == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        #expect(object["createdAt"] as? String == "2027-01-15T08:00:00Z")
    }

    @Test("contract decoder rejects uppercase UUID strings")
    func contractDecoderRejectsUppercaseUUIDStrings() {
        let json = """
        {"id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","name":"Inbox","colorHex":"#112233","createdAt":"2027-01-15T08:00:00Z"}
        """

        expectValidationError(.invalidUUIDString("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")) {
            _ = try decode(Folder.self, from: json)
        }
    }

    @Test("multi-page document JSON uses pages and no legacy asset path fields")
    func multiPageDocumentJSONShape() throws {
        let document = makeDocument(pages: [
            makePage(index: 0),
            makePage(index: 1)
        ])
        let object = try jsonObject(for: document)
        let pages = try #require(object["pages"] as? [[String: Any]])
        let legacyPathFields = ["original", "rectified", "watermarked"].map { "\($0)Path" }

        #expect(pages.count == 2)
        for field in legacyPathFields {
            #expect(object[field] == nil)
        }
        #expect(pages[0]["source"] != nil)
        for field in legacyPathFields {
            #expect(pages[0][field] == nil)
        }
    }

    @Test("decoded invalid stored document fails validation")
    func decodedInvalidStoredDocumentFailsValidation() {
        var document = makeDocument()
        document = StoredDocument(
            id: document.id,
            folderId: document.folderId,
            name: document.name,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            orderIndex: -1,
            pages: document.pages,
            tagIds: document.tagIds
        )

        expectValidationError(.negativeOrderIndex(-1)) {
            let data = try WatakeContractCoding.makeJSONEncoder().encode(document)
            _ = try WatakeContractCoding.makeJSONDecoder().decode(StoredDocument.self, from: data)
        }
    }

    @Test("decoded invalid watermark config fails validation")
    func decodedInvalidWatermarkConfigFailsValidation() {
        let config = makeWatermarkConfig(schemaVersion: 0)

        expectValidationError(.invalidSchemaVersion(0)) {
            let data = try JSONEncoder().encode(config)
            _ = try WatakeContractCoding.makeJSONDecoder().decode(WatermarkConfig.self, from: data)
        }
    }

    @Test("crop quadrilateral validates bounds and corner ordering")
    func cropQuadrilateralValidation() {
        let valid = CropQuadrilateral.unit
        #expect(valid.isValid)

        let invalidDegenerate = CropQuadrilateral(
            topLeft: NormalizedPoint(x: 0.5, y: 0.5),
            topRight: NormalizedPoint(x: 0.5, y: 0.5),
            bottomRight: NormalizedPoint(x: 0.2, y: 0.2),
            bottomLeft: NormalizedPoint(x: 0.2, y: 0.2)
        )
        #expect(!invalidDegenerate.isValid)

        let invalidCrossed = CropQuadrilateral(
            topLeft: NormalizedPoint(x: 0.0, y: 1.0),
            topRight: NormalizedPoint(x: 1.0, y: 1.0),
            bottomRight: NormalizedPoint(x: 0.0, y: 0.0),
            bottomLeft: NormalizedPoint(x: 1.0, y: 0.0)
        )
        #expect(!invalidCrossed.isValid)

        let invalidConcave = CropQuadrilateral(
            topLeft: NormalizedPoint(x: 0.0, y: 1.0),
            topRight: NormalizedPoint(x: 1.0, y: 1.0),
            bottomRight: NormalizedPoint(x: 0.5, y: 0.8),
            bottomLeft: NormalizedPoint(x: 0.0, y: 0.0)
        )
        #expect(!invalidConcave.isValid)
    }

    @Test("ocr text normalizes line endings through decoding")
    func ocrTextNormalizesThroughDecoding() throws {
        let page = makePage(ocrText: "one\r\ntwo\rthree")
        let data = try WatakeContractCoding.makeJSONEncoder().encode(page)
        let decoded = try WatakeContractCoding.makeJSONDecoder().decode(DocumentPage.self, from: data)

        #expect(decoded.ocrText == "one\ntwo\nthree")
    }

    @Test("search normalizes case, diacritics, and whitespace")
    func searchNormalization() {
        let query = DocumentSearchQuery("  CAFE\u{301} \n  REPORT  ")

        #expect(query.normalizedValue == "cafe report")
        #expect(query.matches("Café\tReport"))
        #expect(DocumentSearchQuery(" \n \t ").isEmpty)
    }
}

private struct KeyModels: Codable, Equatable {
    let folder: Folder
    let document: StoredDocument
    let tag: WatakeDomain.Tag
    let preset: WatermarkPreset
    let rendition: WatermarkRendition
    let draft: ExportDraft
}

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
private let validSHA256 = String(repeating: "a", count: 64)
private let uuidWithLetters = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? fixedUUID(40)

private func fixedUUID(_ value: Int) -> UUID {
    let byte = UInt8(value)
    return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
}

private func makeAsset(relativePath: String = "folders/document/source.jpg", sha256Hex: String = validSHA256) -> AssetReference {
    AssetReference(id: fixedUUID(1), relativePath: relativePath, sha256Hex: sha256Hex, byteSize: 12, mediaType: "image/jpeg")
}

private func makePage(index: Int = 0, ocrText: String? = nil) -> DocumentPage {
    DocumentPage(
        id: fixedUUID(4 + index),
        index: index,
        source: makeAsset(relativePath: "folders/document/pages/\(index)/source.jpg"),
        ocrText: ocrText,
        ocrBlocks: [
            OCRBlock(
                id: fixedUUID(100 + index),
                text: "synthetic text",
                bounds: NormalizedRect(originX: 0.1, originY: 0.1, width: 0.2, height: 0.2)
            )
        ]
    )
}

private func makeDocument(pages: [DocumentPage] = [makePage()], tagIds: [UUID] = [fixedUUID(5)]) -> StoredDocument {
    StoredDocument(
        id: fixedUUID(2),
        folderId: fixedUUID(3),
        name: "Document",
        createdAt: fixedDate,
        updatedAt: fixedDate,
        orderIndex: 0,
        pages: pages,
        tagIds: tagIds,
        watermarkPresetId: fixedUUID(6)
    )
}

private func makeTextLayer(opacity: Double = 0.5, rotation: Double = 0) -> WatermarkTextLayer {
    WatermarkTextLayer(
        text: "Verification",
        enabled: true,
        fontName: "Helvetica",
        sizePreset: .medium,
        colorHex: "#000000",
        rotation: rotation,
        opacity: opacity
    )
}

func makeWatermarkConfig(
    schemaVersion: Int = 1,
    globalRotation: Double = 0,
    globalOpacity: Double = 0.5,
    layoutMode: WatermarkLayoutMode = .single,
    tileSpacingX: Double? = nil,
    tileSpacingY: Double? = nil
) -> WatermarkConfig {
    WatermarkConfig(
        schemaVersion: schemaVersion,
        automatic: true,
        body: makeTextLayer(),
        globalPosition: .center,
        globalRotation: globalRotation,
        globalOpacity: globalOpacity,
        layoutMode: layoutMode,
        tileSpacingX: tileSpacingX,
        tileSpacingY: tileSpacingY
    )
}

func expectValidationError(_ expected: DomainValidationError, body: () throws -> Void) {
    do {
        try body()
        Issue.record("Expected \(expected)")
    } catch let error as DomainValidationError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected), got \(error)")
    }
}

private func jsonObject(for value: some Encodable) throws -> [String: Any] {
    let data = try WatakeContractCoding.makeJSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    let data = Data(json.utf8)
    return try WatakeContractCoding.makeJSONDecoder().decode(type, from: data)
}
