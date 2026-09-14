import Foundation
import Testing
import WatakeDomain
@testable import DocumentEditorFeature

@Suite("Document highlight interaction")
struct DocumentHighlightInteractionTests {
    @Test
    func autoStraightenLocksToInitialDominantAxis() {
        let first = InkPoint(location: .init(x: 0.2, y: 0.3))
        let horizontal = InkPoint(location: .init(x: 0.7, y: 0.4))
        let vertical = InkPoint(location: .init(x: 0.25, y: 0.9))

        #expect(DocumentHighlightInteraction.lockAxis(from: first, to: horizontal) == .horizontal)
        #expect(DocumentHighlightInteraction.lockAxis(from: first, to: vertical) == .vertical)
        let locked = DocumentHighlightInteraction.displayedPoints([first, horizontal], axis: .horizontal)
        #expect(locked.last?.location.y == first.location.y)
        #expect(locked.last?.location.x == horizontal.location.x)
    }

    @Test
    func thinStraightHighlightsAlwaysProduceValidGeometry() throws {
        let pageSize = CGSize(width: 390, height: 700)
        for step in 0 ... 1000 {
            let position = Double(step) / 1000
            let horizontal = try #require(DocumentHighlightInteraction.prepare(
                points: [
                    InkPoint(location: .init(x: 0.2, y: position)),
                    InkPoint(location: .init(x: 0.8, y: position))
                ],
                pageSize: pageSize,
                width: 0.008,
                colorHex: "#FBBF24",
                opacity: 0.42
            ))
            let vertical = try #require(DocumentHighlightInteraction.prepare(
                points: [
                    InkPoint(location: .init(x: position, y: 0.2)),
                    InkPoint(location: .init(x: position, y: 0.8))
                ],
                pageSize: pageSize,
                width: 0.008,
                colorHex: "#FBBF24",
                opacity: 0.42
            ))

            try horizontal.transform.validate()
            try horizontal.stroke.validate()
            try vertical.transform.validate()
            try vertical.stroke.validate()
        }
    }

    @Test
    func tapAndTinyFlickDoNotCreateHighlights() {
        let pageSize = CGSize(width: 390, height: 700)
        let tap = InkPoint(location: .init(x: 0.5, y: 0.5))
        let tinyFlick = InkPoint(location: .init(x: 0.505, y: 0.5))

        #expect(DocumentHighlightInteraction.prepare(
            points: [tap, tap], pageSize: pageSize, width: 0.025, colorHex: "#FBBF24", opacity: 0.42
        ) == nil)
        #expect(DocumentHighlightInteraction.prepare(
            points: [tap, tinyFlick], pageSize: pageSize, width: 0.025, colorHex: "#FBBF24", opacity: 0.42
        ) == nil)
    }

    @Test
    func oversizedFreehandPathIsSampledWithinDomainLimit() throws {
        let points = (0 ... 20050).map { index in
            InkPoint(location: .init(x: Double(index) / 20050, y: 0.5))
        }
        let prepared = try #require(DocumentHighlightInteraction.prepare(
            points: points,
            pageSize: CGSize(width: 1000, height: 1000),
            width: 0.025,
            colorHex: "#FBBF24",
            opacity: 0.42
        ))

        #expect(prepared.stroke.points.count == 20000)
        try prepared.stroke.validate()
    }

    @Test
    func capturedFreehandPointsArePeriodicallyReduced() {
        var points: [InkPoint] = []
        for index in 0 ... 25000 {
            DocumentHighlightInteraction.appendCapturedPoint(
                InkPoint(location: .init(x: Double(index) / 25000, y: 0.5)),
                to: &points
            )
        }

        #expect(points.count <= DocumentHighlightInteraction.maximumCapturedPointCount)
        #expect(points.first?.location.x == 0)
        #expect(points.last?.location.x == 1)
    }

    @Test @MainActor
    func releasedHighlightKeepsDrawingModeAndHidesSelection() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.activateTool(.highlight)
        model.setHighlightDrawingColor("#86EFAC")

        model.addHighlight(
            points: [
                InkPoint(location: .init(x: 0.2, y: 0.4)),
                InkPoint(location: .init(x: 0.8, y: 0.4))
            ],
            pageSize: CGSize(width: 500, height: 1000),
            straightened: true
        )

        model.addHighlight(
            points: [
                InkPoint(location: .init(x: 0.25, y: 0.5)),
                InkPoint(location: .init(x: 0.75, y: 0.5))
            ],
            pageSize: CGSize(width: 500, height: 1000),
            straightened: true
        )

        let highlights = model.selectedPage?.annotations ?? []
        #expect(highlights.count == 2)
        #expect(highlights.allSatisfy { $0.kind == .highlight })
        #expect(highlights.allSatisfy { $0.strokes.first?.colorHex == "#86EFAC" })
        let allStraightened = highlights.allSatisfy(\.isStraightened)
        #expect(allStraightened)
        #expect(highlights.allSatisfy { $0.transform.width < 1 })
        #expect(model.selectedAnnotationID == nil)
        #expect(model.tool == .highlight)
    }

    @Test @MainActor
    func freehandHighlightKeepsPathAndViewClearsSelection() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.activateTool(.highlight)
        model.setHighlightAutoStraighten(false)
        let points = [
            InkPoint(location: .init(x: 0.2, y: 0.4)),
            InkPoint(location: .init(x: 0.4, y: 0.5)),
            InkPoint(location: .init(x: 0.7, y: 0.42))
        ]

        model.addHighlight(
            points: points,
            pageSize: CGSize(width: 500, height: 1000),
            straightened: false
        )

        #expect(model.selectedPage?.annotations.first?.strokes.first?.points.count == points.count)
        #expect(model.selectedPage?.annotations.first?.isStraightened == false)
        model.activateTool(.select)
        #expect(model.selectedAnnotationID == nil)
        #expect(model.tool == .select)
    }

    @Test @MainActor
    func changingPageExitsHighlightMode() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.activateTool(.highlight)

        model.selectPage(fixture.secondPageID)

        #expect(model.selectedPageID == fixture.secondPageID)
        #expect(model.tool == .select)
    }

    @Test @MainActor
    func drawingStyleAppliesToNewHighlightsWithoutSelectingOne() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.activateTool(.highlight)
        model.setHighlightDrawingStyle(width: 0.04, colorHex: "#7DD3FC", opacity: 0.68)

        model.addHighlight(
            points: [
                InkPoint(location: .init(x: 0.2, y: 0.4)),
                InkPoint(location: .init(x: 0.8, y: 0.4))
            ],
            pageSize: CGSize(width: 500, height: 1000),
            straightened: true
        )

        let stroke = model.selectedPage?.annotations.first?.strokes.first
        #expect(stroke?.width == 0.04)
        #expect(stroke?.colorHex == "#7DD3FC")
        #expect(stroke?.opacity == 0.68)
        #expect(model.selectedAnnotationID == nil)
        #expect(model.tool == .highlight)
    }

    @Test @MainActor
    func highlightStyleSliderChangesCoalesceIntoOneUndoCommand() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.addHighlight(
            points: [
                InkPoint(location: .init(x: 0.2, y: 0.4)),
                InkPoint(location: .init(x: 0.8, y: 0.4))
            ],
            pageSize: CGSize(width: 500, height: 1000),
            straightened: true
        )
        guard let highlightID = model.selectedPage?.annotations.first?.id else {
            Issue.record("Expected saved highlight")
            return
        }
        model.selectAnnotation(highlightID)

        model.beginContinuousEdit()
        model.updateSelectedStrokeStyle(width: 0.04, colorHex: "#7DD3FC", opacity: 0.6)
        model.updateSelectedStrokeStyle(width: 0.05, colorHex: "#7DD3FC", opacity: 0.7)
        model.endContinuousEdit()
        #expect(model.selectedAnnotation?.strokes.first?.width == 0.05)
        model.undo()
        #expect(model.selectedPage?.annotations.first?.strokes.first?.width == 0.025)
        #expect(model.canUndo)
    }

    @Test @MainActor
    func selectedHighlightStyleDoesNotRewriteDrawingDefaults() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.setHighlightDrawingStyle(width: 0.025, colorHex: "#FBBF24", opacity: 0.42)
        model.addHighlight(
            points: [
                InkPoint(location: .init(x: 0.2, y: 0.4)),
                InkPoint(location: .init(x: 0.8, y: 0.4))
            ],
            pageSize: CGSize(width: 500, height: 1000),
            straightened: true
        )
        guard let firstID = model.selectedPage?.annotations.first?.id else {
            Issue.record("Expected saved highlight")
            return
        }

        model.selectAnnotation(firstID)
        model.updateSelectedStrokeStyle(width: 0.05, colorHex: "#7DD3FC", opacity: 0.75)
        model.activateTool(.highlight)
        model.addHighlight(
            points: [
                InkPoint(location: .init(x: 0.2, y: 0.6)),
                InkPoint(location: .init(x: 0.8, y: 0.6))
            ],
            pageSize: CGSize(width: 500, height: 1000),
            straightened: true
        )

        let strokes = model.selectedPage?.annotations.compactMap(\.strokes.first) ?? []
        #expect(strokes.count == 2)
        #expect(strokes[0].width == 0.05)
        #expect(strokes[0].colorHex == "#7DD3FC")
        #expect(strokes[1].width == 0.025)
        #expect(strokes[1].colorHex == "#FBBF24")
        #expect(strokes[1].opacity == 0.42)
    }

    @Test @MainActor
    func highlightWidthsUseOneSharedRange() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
        model.setHighlightDrawingStyle(width: 0, colorHex: "#FBBF24", opacity: 0.42)
        #expect(model.highlightWidth == DocumentEditorPalette.highlightWidthRange.lowerBound)
        model.setHighlightDrawingStyle(width: 1, colorHex: "#FBBF24", opacity: 0.42)
        #expect(model.highlightWidth == DocumentEditorPalette.highlightWidthRange.upperBound)
    }
}
