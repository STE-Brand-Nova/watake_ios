import Foundation
import WatakeDomain

struct DocumentCopyDestination {
    let name: String
    let folderID: UUID
    let orderIndex: Int
}

func makeDocumentCopy(
    from document: StoredDocument,
    destination: DocumentCopyDestination,
    timestamp: Date,
    makeUUID: () -> UUID
) -> StoredDocument {
    let pages = document.pages.map { page in
        DocumentPage(
            id: makeUUID(), index: page.index, originalIndex: page.originalIndex, source: page.source,
            rectified: page.rectified, ocrText: page.ocrText, ocrBlocks: page.ocrBlocks,
            annotations: page.annotations.map { item in
                PageAnnotation(
                    id: makeUUID(), kind: item.kind, transform: item.transform, opacity: item.opacity,
                    zIndex: item.zIndex, text: item.text, strokes: item.strokes, image: item.image,
                    isStraightened: item.isStraightened,
                    isFlippedHorizontally: item.isFlippedHorizontally,
                    isFlippedVertically: item.isFlippedVertically
                )
            }
        )
    }
    return StoredDocument(
        id: makeUUID(), folderId: destination.folderID, name: destination.name,
        createdAt: timestamp, updatedAt: timestamp,
        orderIndex: destination.orderIndex, pages: pages, tagIds: document.tagIds,
        watermarkPresetId: document.watermarkPresetId
    )
}

func replacingPages(_ document: StoredDocument, pages: [DocumentPage]) -> StoredDocument {
    StoredDocument(
        id: document.id, folderId: document.folderId, name: document.name, createdAt: document.createdAt,
        updatedAt: document.updatedAt, orderIndex: document.orderIndex, pages: pages,
        deletedAt: document.deletedAt, tagIds: document.tagIds, watermarkPresetId: document.watermarkPresetId
    )
}

func replacingDocumentMetadata(_ document: StoredDocument, updatedAt: Date) -> StoredDocument {
    StoredDocument(
        id: document.id, folderId: document.folderId, name: document.name, createdAt: document.createdAt,
        updatedAt: updatedAt, orderIndex: document.orderIndex, pages: document.pages,
        deletedAt: document.deletedAt, tagIds: document.tagIds, watermarkPresetId: document.watermarkPresetId
    )
}

func snap(_ value: Double) -> Double {
    abs(value - 0.5) <= 0.015 ? 0.5 : value
}

func offsetPlacedDuplicate(_ transform: AnnotationTransform) -> AnnotationTransform {
    let offset = 0.03
    let centerX = transform.centerX <= 1 - offset ? transform.centerX + offset : transform.centerX - offset
    let centerY = transform.centerY <= 1 - offset ? transform.centerY + offset : transform.centerY - offset
    return AnnotationTransform(
        centerX: min(max(centerX, 0), 1), centerY: min(max(centerY, 0), 1),
        width: transform.width, height: transform.height, rotation: transform.rotation
    )
}

func normalizedRotation(_ value: Double) -> Double {
    var output = value.truncatingRemainder(dividingBy: 360)
    if output > 180 {
        output -= 360
    }
    if output < -180 {
        output += 360
    }
    return output
}
