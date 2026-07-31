import XCTest
@testable import DesignSystem

final class LayoutTests: XCTestCase {
    func testCompactBelowSevenHundred() {
        XCTAssertEqual(WatakeLayout.widthClass(for: 0), .compact)
        XCTAssertEqual(WatakeLayout.widthClass(for: 390), .compact)
        XCTAssertEqual(WatakeLayout.widthClass(for: 699), .compact)
    }

    func testRegularBoundaries() {
        XCTAssertEqual(WatakeLayout.widthClass(for: 700), .regular)
        XCTAssertEqual(WatakeLayout.widthClass(for: 900), .regular)
        XCTAssertEqual(WatakeLayout.widthClass(for: 1099), .regular)
    }

    func testExpandedFromElevenHundred() {
        XCTAssertEqual(WatakeLayout.widthClass(for: 1100), .expanded)
        XCTAssertEqual(WatakeLayout.widthClass(for: 1440), .expanded)
    }

    func testGuttersPerClass() {
        XCTAssertEqual(WatakeLayout.gutter(for: .compact), 16)
        XCTAssertEqual(WatakeLayout.gutter(for: .regular), 24)
        XCTAssertEqual(WatakeLayout.gutter(for: .expanded), 32)
    }

    func testGutterByWidthMatchesClass() {
        XCTAssertEqual(WatakeLayout.gutter(for: 500), WatakeLayout.gutter(for: .compact))
        XCTAssertEqual(WatakeLayout.gutter(for: 800), WatakeLayout.gutter(for: .regular))
        XCTAssertEqual(WatakeLayout.gutter(for: 1200), WatakeLayout.gutter(for: .expanded))
    }

    func testColumnCounts() {
        XCTAssertEqual(WatakeLayout.columnCount(for: 390), 1)
        XCTAssertEqual(WatakeLayout.columnCount(for: 820), 2)
        XCTAssertEqual(WatakeLayout.columnCount(for: 1366), 3)
    }
}
