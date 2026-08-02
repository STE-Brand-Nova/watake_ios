import CoreGraphics
import Foundation

enum TestPDFReadError: Error {
    case unreadable
}

struct PixelColor {
    let red: Double
    let green: Double
    let blue: Double
}

/// Read-only helpers for asserting on rendered PDF bytes in tests, using
/// real Core Graphics PDF/bitmap inspection rather than mocks.
enum PDFInspection {
    static func pageCount(of pdfData: Data) throws -> Int {
        guard let provider = CGDataProvider(data: pdfData as CFData) else {
            throw TestPDFReadError.unreadable
        }
        guard let document = CGPDFDocument(provider) else {
            throw TestPDFReadError.unreadable
        }
        return document.numberOfPages
    }

    static func pageSizes(of pdfData: Data) throws -> [(width: Double, height: Double)] {
        guard let provider = CGDataProvider(data: pdfData as CFData) else {
            throw TestPDFReadError.unreadable
        }
        guard let document = CGPDFDocument(provider) else {
            throw TestPDFReadError.unreadable
        }
        return (1 ... document.numberOfPages).compactMap { index in
            guard let page = document.page(at: index) else {
                return nil
            }
            let box = page.getBoxRect(.mediaBox)
            return (Double(box.width), Double(box.height))
        }
    }

    static func pageWidths(of pdfData: Data) throws -> [Int] {
        try pageSizes(of: pdfData).map { Int($0.width) }
    }

    /// Rasterizes PDF page 1 and samples the pixel at horizontal position
    /// `column`, measured `yFromTop` pixels down from the top edge, to
    /// verify source image orientation survived rendering.
    static func pixelColor(of pdfData: Data, column: Int, yFromTop: Int) throws -> PixelColor {
        guard let provider = CGDataProvider(data: pdfData as CFData) else {
            throw TestPDFReadError.unreadable
        }
        guard let document = CGPDFDocument(provider), let page = document.page(at: 1) else {
            throw TestPDFReadError.unreadable
        }
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width)
        let height = Int(box.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestPDFReadError.unreadable
        }
        context.drawPDFPage(page)

        // CGBitmapContext stores row 0 as the top of the drawn content
        // regardless of the context's bottom-left drawing origin.
        let offset = (yFromTop * width + column) * 4
        return PixelColor(
            red: Double(pixels[offset]) / 255,
            green: Double(pixels[offset + 1]) / 255,
            blue: Double(pixels[offset + 2]) / 255
        )
    }
}
