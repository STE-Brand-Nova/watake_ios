import Foundation
import Testing
import WatakeDomain
@testable import DocumentEditorFeature
#if canImport(UIKit)
    import SwiftUI
    import UIKit
#endif

@Suite("Document signature editing")
struct DocumentSignatureEditingTests {
    @Test
    func touchDownAtOffsetResizeHandleDoesNotChangeSignature() {
        let transform = AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.36, height: 0.06)
        let pageSize = CGSize(width: 360, height: 720)

        let unchanged = DocumentImageInteraction.resized(
            from: transform,
            corner: .bottomTrailing,
            translation: .zero,
            pageSize: pageSize
        )

        #expect(abs(unchanged.width - transform.width) < 0.000001)
        #expect(abs(unchanged.height - transform.height) < 0.000001)
        #expect(abs(unchanged.centerX - transform.centerX) < 0.000001)
        #expect(abs(unchanged.centerY - transform.centerY) < 0.000001)
        #expect(SignatureSelectionPolicy.usesCompactControls(transform: transform, pageSize: pageSize))
    }

    @Test
    func signatureCornerCanShrinkBelowImageMinimumWithoutChangingAspectRatio() throws {
        let start = AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.36, height: 0.06)
        let pageSize = CGSize(width: 360, height: 720)
        let translation = CGSize(width: -97.2, height: -32.4)

        let resized = DocumentImageInteraction.resized(
            from: start,
            corner: .bottomTrailing,
            translation: translation,
            pageSize: pageSize,
            minimumDimension: 0
        )
        let imageMinimum = DocumentImageInteraction.resized(
            from: start,
            corner: .bottomTrailing,
            translation: translation,
            pageSize: pageSize
        )

        try resized.validate()
        #expect(abs(resized.width - 0.09) < 0.000001)
        #expect(abs(resized.height - 0.015) < 0.000001)
        #expect(abs(resized.width / resized.height - start.width / start.height) < 0.000001)
        #expect(imageMinimum.height * pageSize.height >= 28)
    }

    @Test
    func resizeSheetKeepsSignatureAspectAndDomainMinimum() throws {
        let start = AnnotationTransform(centerX: 0.35, centerY: 0.65, width: 0.4, height: 0.04)
        let range = SignatureResizePolicy.scaleRange(for: start)
        #expect(range.lowerBound == 0.25)

        let smaller = SignatureResizePolicy.resized(start, scale: 0.1)
        try smaller.validate()
        #expect(smaller.width == 0.1)
        #expect(smaller.height == 0.01)
        #expect(smaller.centerX == start.centerX)
        #expect(smaller.centerY == start.centerY)
        #expect(smaller.rotation == start.rotation)
    }

    @Test @MainActor
    func signatureResizeSessionCreatesOneUndoStep() throws {
        let (model, _) = EditorFixture().makeModel()
        _ = model.prepareSignaturePlacement(strokes: signatureStrokes(colorHex: "#0B1220"), aspectRatio: 4)
        _ = model.placePendingSignature(
            transform: AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.4, height: 0.08)
        )
        let original = try #require(model.selectedAnnotation?.transform)

        model.beginContinuousEdit()
        model.transformSelected(width: 0.3, height: 0.06)
        model.transformSelected(width: 0.2, height: 0.04)
        model.endContinuousEdit()

        #expect(model.selectedAnnotation?.transform.width == 0.2)
        model.undo()
        #expect(model.selectedPage?.annotations.first?.transform == original)
    }

    #if canImport(UIKit)
        @Test @MainActor
        func grayscalePickerColorsKeepWhiteAndBlack() {
            #expect(signatureHexColor(Color(uiColor: UIColor(white: 1, alpha: 1))) == "#FFFFFF")
            #expect(signatureHexColor(Color(uiColor: UIColor(white: 0, alpha: 1))) == "#000000")
        }
    #endif

    @Test @MainActor
    func signatureWaitsForPlacementAndKeepsAspectRatio() throws {
        let (model, _) = EditorFixture().makeModel()
        let strokes = signatureStrokes(colorHex: "#0B1220")

        #expect(model.prepareSignaturePlacement(strokes: strokes, aspectRatio: 3))
        #expect(model.selectedPage?.annotations.isEmpty == true)
        #expect(model.pendingSignaturePlacement?.aspectRatio == 3)

        let transform = AnnotationTransform(centerX: 0.4, centerY: 0.6, width: 0.6, height: 0.1)
        #expect(model.placePendingSignature(transform: transform))

        let annotation = try #require(model.selectedAnnotation)
        #expect(annotation.kind == .signature)
        #expect(annotation.transform == transform)
        #expect(annotation.strokes == strokes)
        #expect(model.pendingSignaturePlacement == nil)
        #expect(model.tool == .select)
    }

    @Test @MainActor
    func cancellingSignaturePlacementDoesNotCreateUndoHistory() {
        let (model, _) = EditorFixture().makeModel()
        _ = model.prepareSignaturePlacement(strokes: signatureStrokes(colorHex: "#0B1220"), aspectRatio: 2)

        model.cancelSignaturePlacement()

        #expect(model.pendingSignaturePlacement == nil)
        #expect(model.selectedPage?.annotations.isEmpty == true)
        #expect(!model.canUndo)
        #expect(model.tool == .select)
    }

    @Test @MainActor
    func invalidSignaturePlacementExitsPlacementWithFeedback() {
        let (model, _) = EditorFixture().makeModel()
        _ = model.prepareSignaturePlacement(strokes: signatureStrokes(colorHex: "#0B1220"), aspectRatio: 2)

        let invalid = AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.001, height: 0.1)
        #expect(!model.placePendingSignature(transform: invalid))
        #expect(model.pendingSignaturePlacement == nil)
        #expect(model.tool == .select)
        #expect(model.selectedPage?.annotations.isEmpty == true)
        #expect(model.errorMessage == "Signature could not be placed. Add it again.")
        #expect(!model.canUndo)
    }

    @Test @MainActor
    func invalidPendingSignaturePayloadAlsoExitsPlacement() throws {
        let (model, _) = EditorFixture().makeModel()
        let points = try #require(signatureStrokes(colorHex: "#0B1220").first?.points)
        model.pendingSignaturePlacement = PendingSignaturePlacement(
            id: UUID(),
            strokes: [InkStroke(points: points, width: 0.02, colorHex: "#ZZZZZZ")],
            aspectRatio: 2
        )
        model.tool = .signature

        #expect(!model.placePendingSignature(
            transform: AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.4, height: 0.1)
        ))
        #expect(model.pendingSignaturePlacement == nil)
        #expect(model.tool == .select)
        #expect(model.selectedPage?.annotations.isEmpty == true)
        #expect(model.errorMessage == "Signature could not be placed. Add it again.")
    }

    @Test @MainActor
    func reuseSaveFailureCanBeHandledInSheetAndRetried() async {
        let (model, store) = EditorFixture().makeModel()
        await store.failNextSignatureSave()
        let strokes = signatureStrokes(colorHex: "#0B1220")

        #expect(await !(model.saveSignature(
            name: "Work", strokes: strokes, aspectRatio: 2, reportFailure: false
        )))
        #expect(model.errorMessage == nil)
        #expect(model.signatures.isEmpty)

        #expect(await model.saveSignature(
            name: "Work", strokes: strokes, aspectRatio: 2, reportFailure: false
        ))
        #expect(model.signatures.count == 1)
    }

    @Test @MainActor
    func successfulReuseSaveDoesNotDependOnListRefresh() async {
        let (model, store) = EditorFixture().makeModel()
        await store.failNextSignatureLoad()

        #expect(await model.saveSignature(
            name: "Work", strokes: signatureStrokes(colorHex: "#0B1220"), aspectRatio: 2,
            reportFailure: false
        ))
        #expect(model.signatures.count == 1)
        #expect(model.errorMessage == nil)
    }

    @Test @MainActor
    func placedCopiesKeepIndependentColorAndPosition() throws {
        let (model, _) = EditorFixture().makeModel()
        let strokes = signatureStrokes(colorHex: "#0B1220")
        _ = model.prepareSignaturePlacement(strokes: strokes, aspectRatio: 2)
        _ = model.placePendingSignature(
            transform: AnnotationTransform(centerX: 0.4, centerY: 0.5, width: 0.4, height: 0.1)
        )
        let original = try #require(model.selectedAnnotation)

        model.duplicateSelected()
        let duplicate = try #require(model.selectedAnnotation)
        model.updateSelectedSignatureColor("#B91C1C")

        let annotations = try #require(model.selectedPage?.annotations)
        let unchangedOriginal = try #require(annotations.first(where: { $0.id == original.id }))
        let changedDuplicate = try #require(annotations.first(where: { $0.id == duplicate.id }))
        #expect(unchangedOriginal.strokes.first?.colorHex == "#0B1220")
        #expect(changedDuplicate.strokes.first?.colorHex == "#B91C1C")
        #expect(changedDuplicate.transform.centerX != unchangedOriginal.transform.centerX)
        #expect(changedDuplicate.transform.centerY != unchangedOriginal.transform.centerY)
    }

    @Test @MainActor
    func deletingSavedSignatureDoesNotDeletePlacedCopy() async throws {
        let (model, _) = EditorFixture().makeModel()
        let strokes = signatureStrokes(colorHex: "#1F4FEB")
        #expect(await model.saveSignature(name: "Work", strokes: strokes, aspectRatio: 2.5))
        let saved = try #require(model.signatures.first)
        model.applySignature(saved)
        _ = model.placePendingSignature(
            transform: AnnotationTransform(centerX: 0.5, centerY: 0.5, width: 0.5, height: 0.1)
        )

        #expect(await model.deleteSavedSignature(id: saved.id))

        #expect(model.signatures.isEmpty)
        #expect(model.selectedPage?.annotations.first?.kind == .signature)
        #expect(model.selectedPage?.annotations.first?.strokes == strokes)
    }

    private func signatureStrokes(colorHex: String) -> [InkStroke] {
        [InkStroke(
            points: [
                InkPoint(location: NormalizedPoint(x: 0, y: 0.8)),
                InkPoint(location: NormalizedPoint(x: 0.5, y: 0.2)),
                InkPoint(location: NormalizedPoint(x: 1, y: 0.7))
            ],
            width: 0.02,
            colorHex: colorHex
        )]
    }
}
