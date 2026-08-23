import DesignSystem
import SwiftUI
import UIKit
import WatakeDomain

struct DocumentThumbnail: View {
    @Bindable var store: LibraryStore
    let document: StoredDocument
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc.text.image")
                        .foregroundStyle(WatakeColor.text.secondary)
                }
            }
            if document.hasOCRText {
                OCRBadge()
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
        .accessibilityHidden(true)
        .task(id: document.id) {
            guard let data = await store.thumbnailData(for: document) else { return }
            image = UIImage(data: data)
        }
    }
}

struct DocumentGridThumbnail: View {
    @Bindable var store: LibraryStore
    let document: StoredDocument
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc.text.image")
                        .foregroundStyle(WatakeColor.text.secondary)
                }
            }
            if document.hasOCRText {
                OCRBadge()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
        .accessibilityHidden(true)
        .task(id: document.id) {
            guard let data = await store.thumbnailData(for: document) else { return }
            image = UIImage(data: data)
        }
    }
}

private struct OCRBadge: View {
    var body: some View {
        Text("T")
            .watakeType(.caption)
            .foregroundStyle(WatakeColor.text.onPrimary)
            .padding(WatakeSpacing.xxs)
            .background(WatakeColor.brand.primary)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

func documentAccessibilityLabel(_ document: StoredDocument) -> String {
    let OCRSuffix = document.hasOCRText ? ", extracted text available" : ""
    return "\(document.name), \(document.pages.count) pages\(OCRSuffix)"
}
