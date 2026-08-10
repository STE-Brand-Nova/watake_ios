//
//  ExportProgressOverlay.swift
//  ExportFeature
//

import DesignSystem
import SwiftUI
import WatakeDomain

public struct ExportProgressOverlay: View {
    private let progress: ExportProgress
    private let onCancel: () -> Void

    public init(progress: ExportProgress, onCancel: @escaping () -> Void) {
        self.progress = progress
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            WatakeColor.scrim
                .ignoresSafeArea()

            WatakeCard(surface: .raised) {
                VStack(spacing: WatakeSpacing.lg) {
                    Text(String(localized: "Exporting PDF...", comment: "Title for export progress"))
                        .watakeType(.title2)
                        .foregroundStyle(WatakeColor.text.primary)

                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(WatakeColor.brand.primary)
                        .animation(nil, value: progress.fraction) // Reduced motion, static progress

                    HStack {
                        Text(phaseText(for: progress.phase))
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)

                        Spacer()

                        Text(String(localized: "Page \(progress.completedPages) of \(progress.totalPages)", comment: "Progress page count"))
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)
                    }

                    WatakeButton(
                        String(localized: "Cancel", comment: "Cancel export button"),
                        variant: .secondary,
                        action: onCancel
                    )
                }
                .padding(WatakeSpacing.lg)
            }
            .frame(maxWidth: 320)
        }
    }

    private func phaseText(for phase: ExportPhase) -> String {
        switch phase {
        case .preparing:
            String(localized: "Preparing...", comment: "Preparing phase text")
        case .rendering:
            String(localized: "Rendering pages...", comment: "Rendering phase text")
        case .finishing:
            String(localized: "Finishing...", comment: "Finishing phase text")
        }
    }
}
