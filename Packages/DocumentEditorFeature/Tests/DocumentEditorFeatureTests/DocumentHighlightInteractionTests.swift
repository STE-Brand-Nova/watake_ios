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
    func releasedHighlightUsesChosenColorAndBecomesSelected() {
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

        #expect(model.selectedAnnotation?.kind == .highlight)
        #expect(model.selectedAnnotation?.strokes.first?.colorHex == "#86EFAC")
        #expect(model.selectedAnnotation?.isStraightened == true)
        #expect(model.selectedAnnotation?.transform.width ?? 1 < 1)
        #expect(model.selectedAnnotation?.transform.height ?? 1 < 0.1)
        #expect(model.tool == .select)
    }

    @Test @MainActor
    func freehandHighlightKeepsPathAndViewClearsSelection() {
        let fixture = EditorFixture()
        let (model, _) = fixture.makeModel()
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

        #expect(model.selectedAnnotation?.strokes.first?.points.count == points.count)
        #expect(model.selectedAnnotation?.isStraightened == false)
        model.activateTool(.select)
        #expect(model.selectedAnnotationID == nil)
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
