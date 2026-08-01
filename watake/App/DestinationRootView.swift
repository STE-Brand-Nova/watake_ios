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

    var body: some View {
        WatakeEmptyState(
            systemImage: destination.systemImage,
            title: destination.label,
            message: message
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatakeColor.surface.base)
        .navigationTitle(destination.label)
        .watakeAccessibilityIdentifier("destination.\(destination.rawValue)")
    }

    private var message: String {
        switch destination {
        case .library: "Folders you create will appear here."
        case .capture: "Capture is not built yet."
        case .search: "Search is not built yet."
        case .trash: "Deleted items are not built yet."
        case .settings: "Settings are not built yet."
        }
    }
}
