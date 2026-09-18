import Foundation
import WatakeDomain

extension DocumentEditorModel {
    public func addSignature(strokes: [InkStroke]) {
        guard !strokes.isEmpty else { return }
        let annotation = PageAnnotation(
            id: makeUUID(),
            kind: .signature,
            transform: .init(centerX: 0.5, centerY: 0.72, width: 0.42, height: 0.16),
            zIndex: nextZIndex,
            strokes: strokes
        )
        append(annotation)
    }

    public func applySignature(_ signature: SavedSignature) {
        prepareSignaturePlacement(strokes: signature.strokes, aspectRatio: signature.aspectRatio)
    }

    @discardableResult
    public func prepareSignaturePlacement(strokes: [InkStroke], aspectRatio: Double) -> Bool {
        guard !strokes.isEmpty,
              strokes.allSatisfy({ (try? $0.validate()) != nil }),
              aspectRatio.isFinite, aspectRatio >= 0.02, aspectRatio <= 50 else { return false }
        pendingImagePlacement = nil
        pendingSignaturePlacement = PendingSignaturePlacement(
            id: makeUUID(),
            strokes: strokes,
            aspectRatio: aspectRatio
        )
        selectedAnnotationID = nil
        tool = .signature
        return true
    }

    public func cancelSignaturePlacement() {
        pendingSignaturePlacement = nil
        if tool == .signature {
            tool = .select
        }
    }

    @discardableResult
    public func placePendingSignature(transform: AnnotationTransform) -> Bool {
        guard let pendingSignaturePlacement,
              (try? transform.validate()) != nil else { return false }
        let annotation = PageAnnotation(
            id: makeUUID(),
            kind: .signature,
            transform: transform,
            zIndex: nextZIndex,
            strokes: pendingSignaturePlacement.strokes
        )
        guard (try? annotation.validate()) != nil else { return false }
        self.pendingSignaturePlacement = nil
        append(annotation)
        return true
    }

    public func saveSignature(name: String, strokes: [InkStroke], aspectRatio: Double) async -> Bool {
        let timestamp = now()
        let signature = SavedSignature(
            id: makeUUID(), name: name, strokes: strokes, aspectRatio: aspectRatio,
            createdAt: timestamp, updatedAt: timestamp
        )
        do {
            try signature.validate()
            try await store.saveSignature(signature)
            signatures = try await store.savedSignatures()
            return true
        } catch {
            errorMessage = "Signature could not be saved."
            return false
        }
    }

    public func deleteSavedSignature(id: UUID) async -> Bool {
        do {
            try await store.deleteSignature(id: id)
            signatures = try await store.savedSignatures()
            return true
        } catch {
            errorMessage = "Signature could not be deleted."
            return false
        }
    }

    public func updateSelectedSignatureColor(_ colorHex: String) {
        guard selectedAnnotation?.kind == .signature else { return }
        replaceSelected { current in
            let strokes = current.strokes.map {
                InkStroke(points: $0.points, width: $0.width, colorHex: colorHex, opacity: $0.opacity)
            }
            guard strokes.allSatisfy({ (try? $0.validate()) != nil }) else { return current }
            return PageAnnotation(
                id: current.id, kind: current.kind, transform: current.transform, opacity: current.opacity,
                zIndex: current.zIndex, text: current.text, strokes: strokes, image: current.image,
                isStraightened: current.isStraightened,
                isFlippedHorizontally: current.isFlippedHorizontally,
                isFlippedVertically: current.isFlippedVertically
            )
        }
    }
}
