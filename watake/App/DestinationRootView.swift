//
//  DestinationRootView.swift
//  watake
//

import DesignSystem
import SwiftUI

/// Minimal, truthful root content for a top-level destination. No feature
/// behavior (capture, storage, OCR, watermarking, search, trash, settings)
/// is implemented here — that arrives in later slices.
struct DestinationRootView: View {
    let destination: AppDestination
    @Bindable var library: LibraryStore

    var body: some View {
        Group {
            switch destination {
            case .library:
                LibraryView(store: library)
            case .capture:
                CaptureView(store: library)
            case .trash:
                TrashView(store: library)
            case .search, .settings:
                WatakeEmptyState(systemImage: destination.systemImage, title: destination.label, message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WatakeColor.surface.base)
                    .navigationTitle(destination.label)
            }
        }
        .watakeAccessibilityIdentifier("destination.\(destination.rawValue)")
    }

    private var message: String {
        destination == .search ? "Search is not built yet." : "Settings are not built yet."
    }
}
