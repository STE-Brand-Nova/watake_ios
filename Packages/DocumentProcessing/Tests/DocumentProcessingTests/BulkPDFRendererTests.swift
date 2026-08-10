import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import WatakeDomain
@testable import DocumentProcessing

@Suite("BulkPDFRenderer Tests")
struct BulkPDFRendererTests {
    // MARK: - Mocks & Helpers

    actor MockAssetStore: DocumentAssetStore {
        var mockedData: [UUID: Data] = [:]
        var shouldThrow = false
        var throwAfterPage: Int?
        var onRead: (@Sendable () -> Void)?

        private var readCount = 0

        func saveAsset(_ data: Data, reference: AssetReference) async throws {}
        func containsAsset(_ reference: AssetReference) async throws -> Bool {
            true
        }

        func removeAsset(_ reference: AssetReference) async throws {}

        func readAsset(_ reference: AssetReference) async throws -> Data {
            onRead?()
            if shouldThrow {
                throw NSError(domain: "MockError", code: 1, userInfo: nil)
            }
            if let max = throwAfterPage, readCount >= max {
                throw NSError(domain: "MockError", code: 2, userInfo: nil)
            }
            readCount += 1
            if let data = mockedData[reference.id] {
                return data
            }
            // Return default synthetic data if none matched
            return Self.generateJPEG(width: 100, height: 100)
        }

        static func generateJPEG(width: Int, height: Int) -> Data {
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return Data()
            }

            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            guard let cgImage = context.makeImage() else { return Data() }

            let data = NSMutableData()
            guard let finalDest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
                return Data()
            }
            CGImageDestinationAddImage(finalDest, cgImage, nil)
            CGImageDestinationFinalize(finalDest)
            return data as Data
        }
    }

    func makeJob(
        pages: [PDFRenderPage],
        pageSize: ExportPageSize = .original,
        fitMode: ExportFitMode = .fit,
        marginPoints: Double = 0
    ) -> PDFRenderJob {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        return PDFRenderJob(
            pages: pages,
            pageSize: pageSize,
            fitMode: fitMode,
            marginPoints: marginPoints,
            outputURL: tempURL
        )
    }

    func makePage(id: UUID = UUID()) -> PDFRenderPage {
        PDFRenderPage(
            id: id,
            assetReference: AssetReference(id: id, relativePath: "test.jpg", sha256Hex: "abc", byteSize: 1024, mediaType: nil)
        )
    }

    func readPDFMediaBoxes(url: URL) -> [CGRect] {
        guard let pdf = CGPDFDocument(url as CFURL) else { return [] }
        var boxes: [CGRect] = []
        for pageIndex in 1 ... pdf.numberOfPages {
            if let page = pdf.page(at: pageIndex) {
                let box = page.getBoxRect(.mediaBox)
                boxes.append(box)
            }
        }
        return boxes
    }

    // MARK: - Tests

    @Test
    func correctPageCountAndOrder() async throws {
        let store = MockAssetStore()

        let page1 = makePage()
        let page2 = makePage()
        let page3 = makePage()

        // Page 1: 100x200
        // Page 2: 200x100
        // Page 3: 150x150
        await store.setMockData(page1.id, data: MockAssetStore.generateJPEG(width: 100, height: 200))
        await store.setMockData(page2.id, data: MockAssetStore.generateJPEG(width: 200, height: 100))
        await store.setMockData(page3.id, data: MockAssetStore.generateJPEG(width: 150, height: 150))

        let job = makeJob(pages: [page1, page2, page3], pageSize: .original)
        let renderer = BulkPDFRenderer(assetStore: store)

        let outputURL = try await renderer.renderPDF(job: job) { _ in }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let boxes = readPDFMediaBoxes(url: outputURL)
        #expect(boxes.count == 3)
        #expect(boxes[0].width == 100 && boxes[0].height == 200)
        #expect(boxes[1].width == 200 && boxes[1].height == 100)
        #expect(boxes[2].width == 150 && boxes[2].height == 150)
    }

    @Test
    func a4MediaBoxes() async throws {
        let store = MockAssetStore()
        let page1 = makePage() // Portrait
        let page2 = makePage() // Landscape

        await store.setMockData(page1.id, data: MockAssetStore.generateJPEG(width: 100, height: 200))
        await store.setMockData(page2.id, data: MockAssetStore.generateJPEG(width: 200, height: 100))

        let job = makeJob(pages: [page1, page2], pageSize: .a4)
        let renderer = BulkPDFRenderer(assetStore: store)

        let outputURL = try await renderer.renderPDF(job: job) { _ in }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let boxes = readPDFMediaBoxes(url: outputURL)
        let a4Portrait = try #require(ExportPageSize.a4.portraitDimensions)

        // Portrait
        #expect(abs(boxes[0].width - a4Portrait.width) < 0.1)
        #expect(abs(boxes[0].height - a4Portrait.height) < 0.1)

        // Landscape
        #expect(abs(boxes[1].width - a4Portrait.height) < 0.1)
        #expect(abs(boxes[1].height - a4Portrait.width) < 0.1)
    }

    @Test
    func uSLetterPortraitMediaBox() async throws {
        let store = MockAssetStore()
        let page1 = makePage()

        await store.setMockData(page1.id, data: MockAssetStore.generateJPEG(width: 100, height: 200))

        let job = makeJob(pages: [page1], pageSize: .usLetter)
        let renderer = BulkPDFRenderer(assetStore: store)

        let outputURL = try await renderer.renderPDF(job: job) { _ in }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let boxes = readPDFMediaBoxes(url: outputURL)
        let usLetter = try #require(ExportPageSize.usLetter.portraitDimensions)

        #expect(abs(boxes[0].width - usLetter.width) < 0.1)
        #expect(abs(boxes[0].height - usLetter.height) < 0.1)
    }

    @Test
    func progressIsMonotonic() async throws {
        let store = MockAssetStore()
        let page1 = makePage()
        let page2 = makePage()
        let page3 = makePage()

        let job = makeJob(pages: [page1, page2, page3])
        let renderer = BulkPDFRenderer(assetStore: store)

        let recorder = ProgressRecorder()
        _ = try await renderer.renderPDF(job: job) { progress in
            recorder.append(progress.completedPages)
        }

        let recorded = recorder.recorded
        #expect(recorded == [0, 0, 1, 2, 3])
    }

    @Test
    func cancellationRemovesPartialFile() async throws {
        let store = MockAssetStore()
        let page1 = makePage()
        let page2 = makePage()
        let job = makeJob(pages: [page1, page2])

        let task = Task {
            let renderer = BulkPDFRenderer(assetStore: store)
            return try await renderer.renderPDF(job: job) { _ in
                // NOP
            }
        }

        await store.setOnRead {
            task.cancel()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(!FileManager.default.fileExists(atPath: job.outputURL.path))
    }

    @Test
    func readFailureProducesErrorAndRemovesPartialFile() async throws {
        let store = MockAssetStore()
        await store.setShouldThrow(true)

        let page1 = makePage()
        let job = makeJob(pages: [page1])
        let renderer = BulkPDFRenderer(assetStore: store)

        var caughtError: Error?
        do {
            _ = try await renderer.renderPDF(job: job) { _ in }
        } catch {
            caughtError = error
        }

        #expect(caughtError as? ExportError == ExportError.assetUnreadable(pageID: page1.id))
        #expect(!FileManager.default.fileExists(atPath: job.outputURL.path))
    }

    @Test
    func outputFileExistsAndIsReadableAfterSuccess() async throws {
        let store = MockAssetStore()
        let page1 = makePage()
        let job = makeJob(pages: [page1])
        let renderer = BulkPDFRenderer(assetStore: store)

        let url = try await renderer.renderPDF(job: job) { _ in }
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(FileManager.default.isReadableFile(atPath: url.path))
    }

    @Test
    func largeScannedPageFillsA4ContentRectCorrectly() async throws {
        let store = MockAssetStore()
        let page1 = makePage()
        // Large scanned page (3000 x 4000)
        await store.setMockData(page1.id, data: MockAssetStore.generateJPEG(width: 3000, height: 4000))

        let job = makeJob(pages: [page1], pageSize: .a4, fitMode: .fit)
        let renderer = BulkPDFRenderer(assetStore: store)

        let outputURL = try await renderer.renderPDF(job: job) { _ in }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let boxes = readPDFMediaBoxes(url: outputURL)
        let a4Dims = try #require(ExportPageSize.a4.portraitDimensions)
        #expect(abs(boxes[0].width - a4Dims.width) < 0.1)
        #expect(abs(boxes[0].height - a4Dims.height) < 0.1)

        // Verify PDF document is valid and has 1 page
        guard let pdf = CGPDFDocument(outputURL as CFURL) else {
            Issue.record("PDF document should be readable")
            return
        }
        #expect(pdf.numberOfPages == 1)

        // Rasterize PDF page and verify exact rendered non-white content bounds
        let contentBounds = try #require(rasterizeAndFindNonWhiteBounds(url: outputURL))
        // Expected fit width: full A4 page width (~595pt)
        #expect(abs(contentBounds.width - a4Dims.width) < 3.0)
        // Expected fit height: 4000 * (595.28 / 3000) = ~793.7pt
        let expectedHeight = 4000.0 * (a4Dims.width / 3000.0)
        #expect(abs(contentBounds.height - expectedHeight) < 4.0)
        // Expected vertical centering: (841.89 - 793.7) / 2 = ~24.1pt
        let expectedMinY = (a4Dims.height - expectedHeight) / 2.0
        #expect(abs(contentBounds.minY - expectedMinY) < 4.0)
    }

    private func rasterizeAndFindNonWhiteBounds(url: URL) -> CGRect? {
        guard let pdf = CGPDFDocument(url as CFURL),
              let pdfPage = pdf.page(at: 1) else { return nil }

        let mediaBox = pdfPage.getBoxRect(.mediaBox)
        let width = Int(ceil(mediaBox.width))
        let height = Int(ceil(mediaBox.height))

        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.saveGState()
        let pdfRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let transform = pdfPage.getDrawingTransform(.mediaBox, rect: pdfRect, rotate: 0, preserveAspectRatio: true)
        context.concatenate(transform)
        context.drawPDFPage(pdfPage)
        context.restoreGState()

        guard let pixelData = context.data else { return nil }
        let pointer = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        return nonWhiteBounds(pointer: pointer, width: width, height: height)
    }

    /// Scans an RGBA pixel buffer and returns the tight bounding rect of pixels
    /// darker than near-white on any channel, or nil if none are found.
    private func nonWhiteBounds(pointer: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> CGRect? {
        var minX = width, maxX = 0, minY = height, maxY = 0
        var foundNonWhite = false

        for rowY in 0 ..< height {
            for colX in 0 ..< width {
                let offset = (rowY * width + colX) * 4
                let isWhite = pointer[offset] >= 240 && pointer[offset + 1] >= 240 && pointer[offset + 2] >= 240
                if isWhite {
                    continue
                }

                foundNonWhite = true
                minX = min(minX, colX)
                maxX = max(maxX, colX)
                minY = min(minY, rowY)
                maxY = max(maxY, rowY)
            }
        }

        guard foundNonWhite else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

extension BulkPDFRendererTests.MockAssetStore {
    func setMockData(_ id: UUID, data: Data) {
        mockedData[id] = data
    }

    func setShouldThrow(_ throwFlag: Bool) {
        shouldThrow = throwFlag
    }

    func setOnRead(_ block: @escaping @Sendable () -> Void) {
        onRead = block
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _recorded: [Int] = []

    var recorded: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _recorded
    }

    func append(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        _recorded.append(value)
    }
}
