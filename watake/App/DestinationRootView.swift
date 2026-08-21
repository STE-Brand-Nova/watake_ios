//
//  DestinationRootView.swift
//  watake
//

import DesignSystem
import SwiftUI
import WatakeDomain

/// Minimal, truthful root content for a top-level destination. No feature
/// behavior (capture, storage, OCR, watermarking, search, trash, settings)
/// is implemented here — that arrives in later slices.
struct DestinationRootView: View {
    let destination: AppDestination
    @Bindable var library: LibraryStore
    let onOpenSearchResult: (ArchiveSearchResult) -> Void
    let onOpenCopies: () -> Void
    let onOpenOriginal: (StoredDocument) -> Void
    let onCaptureSaved: (UUID) -> Void

    var body: some View {
        Group {
            switch destination {
            case .library:
                LibraryView(store: library, onOpenCopies: onOpenCopies)
            case .capture:
                CaptureView(store: library, onSaved: onCaptureSaved)
            case .trash:
                TrashView(store: library)
            case .copies:
                WatermarkedCopiesView(store: library, onOpenOriginal: onOpenOriginal)
            case .settings:
                WatakeEmptyState(systemImage: destination.systemImage, title: destination.label, message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WatakeColor.surface.base)
                    .navigationTitle(destination.label)
            }
        }
        .watakeAccessibilityIdentifier("destination.\(destination.rawValue)")
    }

    private var message: String {
        "Settings are not built yet."
    }
}
