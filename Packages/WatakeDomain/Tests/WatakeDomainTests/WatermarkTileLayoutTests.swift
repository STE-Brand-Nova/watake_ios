import Testing
@testable import WatakeDomain

@Suite("WatermarkTileLayoutCalculator")
struct WatermarkTileLayoutTests {
    @Test("same spacing always produces the same points")
    func deterministic() {
        let first = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: 0.35, tileSpacingY: 0.28)
        let second = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: 0.35, tileSpacingY: 0.28)

        #expect(first == second)
    }

    @Test("grid includes the page center for default spacing")
    func includesCenterForDefaultSpacing() {
        let points = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: 0.35, tileSpacingY: 0.28)

        #expect(points.contains(WatermarkTilePoint(normalizedX: 0.5, normalizedY: 0.5)))
    }

    @Test("grid includes the page center for arbitrary spacing", arguments: [(0.10, 0.10), (0.5, 0.75), (1.0, 1.0)])
    func includesCenterForArbitrarySpacing(_ spacing: (x: Double, y: Double)) {
        let points = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: spacing.x, tileSpacingY: spacing.y)

        #expect(points.contains(WatermarkTilePoint(normalizedX: 0.5, normalizedY: 0.5)))
    }

    @Test("grid has no duplicate positions")
    func noDuplicatePositions() {
        let points = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: 0.35, tileSpacingY: 0.28)
        let keys = Set(points.map { "\($0.normalizedX)-\($0.normalizedY)" })

        #expect(keys.count == points.count)
    }

    @Test("minimum spacing reaches the exact hard cap of 121 tiles")
    func minimumSpacingReachesExactCap() {
        let points = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: 0.10, tileSpacingY: 0.10)

        #expect(points.count == 121)
        #expect(points.count == WatermarkTileLayoutCalculator.maximumTileCount)
    }

    @Test("hard cap holds for invalid or degenerate spacing")
    func hardCapHoldsForDegenerateSpacing() {
        let inputs: [(Double, Double)] = [(0, 0), (-1, -1), (.nan, .nan), (.infinity, .infinity), (0.0001, 0.0001)]

        for (spacingX, spacingY) in inputs {
            let points = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: spacingX, tileSpacingY: spacingY)
            #expect(points.count <= WatermarkTileLayoutCalculator.maximumTileCount)
            for point in points {
                #expect(point.normalizedX.isFinite)
                #expect(point.normalizedY.isFinite)
            }
        }
    }

    @Test("points are ordered row-major")
    func orderedRowMajor() {
        let points = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: 0.35, tileSpacingY: 0.28)

        let normalizedYs = points.map(\.normalizedY)
        let sortedYs = normalizedYs.sorted()
        #expect(normalizedYs == sortedYs)
    }

    @Test("normalized points cover past both edges regardless of page aspect ratio")
    func coversPastEdgesForAnyAspectRatio() {
        let points = WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: 0.35, tileSpacingY: 0.28)

        #expect(points.contains { $0.normalizedX < 0 })
        #expect(points.contains { $0.normalizedX > 1 })
        #expect(points.contains { $0.normalizedY < 0 })
        #expect(points.contains { $0.normalizedY > 1 })
    }

    @Test("config convenience returns a single center point for single layout")
    func configConvenienceReturnsSinglePointForSingleLayout() {
        let config = WatermarkConfig(
            automatic: true,
            body: WatermarkTextLayer(
                text: "Verification",
                enabled: true,
                fontName: "Helvetica",
                sizePreset: .medium,
                colorHex: "#000000",
                rotation: 0,
                opacity: 0.5
            ),
            globalPosition: .center,
            globalRotation: 0,
            globalOpacity: 0.5
        )

        let points = WatermarkTileLayoutCalculator.tilePoints(for: config)

        #expect(points == [WatermarkTilePoint(normalizedX: 0.5, normalizedY: 0.5)])
    }

    @Test("config convenience returns the tiled grid for tiled layout")
    func configConvenienceReturnsTiledGridForTiledLayout() {
        let config = WatermarkConfig(
            automatic: true,
            body: WatermarkTextLayer(
                text: "Verification",
                enabled: true,
                fontName: "Helvetica",
                sizePreset: .medium,
                colorHex: "#000000",
                rotation: 0,
                opacity: 0.5
            ),
            globalPosition: .center,
            globalRotation: 0,
            globalOpacity: 0.5,
            layoutMode: .tiled,
            tileSpacingX: 0.35,
            tileSpacingY: 0.28
        )

        let points = WatermarkTileLayoutCalculator.tilePoints(for: config)

        #expect(points == WatermarkTileLayoutCalculator.tilePoints(tileSpacingX: 0.35, tileSpacingY: 0.28))
    }
}
