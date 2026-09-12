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
}
