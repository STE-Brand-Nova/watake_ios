import Foundation

/// Minimal copy metadata displayed beside an original document. Rendered
/// assets stay in the Copies feature; the viewer only needs identity and
/// recipient/version context.
public struct DocumentWatermarkedCopySummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let recipientName: String
    public let version: Int
    public let createdAt: Date

    public init(id: UUID, recipientName: String, version: Int, createdAt: Date) {
        self.id = id
        self.recipientName = recipientName
        self.version = version
        self.createdAt = createdAt
    }
}

public enum DocumentWatermarkedCopyStripPolicy {
    public static let maximumVisibleCopies = 3

    public static func visibleCopies(
        from copies: [DocumentWatermarkedCopySummary]
    ) -> [DocumentWatermarkedCopySummary] {
        Array(
            copies.sorted {
                if $0.createdAt == $1.createdAt {
                    if $0.version != $1.version {
                        return $0.version > $1.version
                    }
                    let recipientOrder = $0.recipientName.localizedCaseInsensitiveCompare($1.recipientName)
                    if recipientOrder != .orderedSame {
                        return recipientOrder == .orderedAscending
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt > $1.createdAt
            }
            .prefix(maximumVisibleCopies)
        )
    }
}

#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    struct DocumentWatermarkedCopiesStrip: View {
        let copies: [DocumentWatermarkedCopySummary]
        let onOpenCopy: (UUID) -> Void
        let onViewAll: () -> Void

        private var visibleCopies: [DocumentWatermarkedCopySummary] {
            DocumentWatermarkedCopyStripPolicy.visibleCopies(from: copies)
        }

        var body: some View {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: WatakeSpacing.sm) {
                    Label(copyCountLabel, systemImage: "doc.on.doc")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                        .fixedSize(horizontal: true, vertical: false)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: WatakeSpacing.xs) {
                            ForEach(visibleCopies) { copy in
                                Button {
                                    onOpenCopy(copy.id)
                                } label: {
                                    WatakeTagChip("\(copy.recipientName) · v\(copy.version)")
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    "Copy for \(copy.recipientName), version \(copy.version)"
                                )
                                .accessibilityHint("Opens this watermarked copy")
                            }
                        }
                    }

                    Button(action: onViewAll) {
                        Image(systemName: "chevron.right.circle")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WatakeColor.brand.primary)
                    .accessibilityLabel("View all watermarked copies")
                    .accessibilityValue(copyCountLabel)
                }
                .padding(.horizontal, WatakeSpacing.md)
                .padding(.vertical, WatakeSpacing.xxs)
                .background(WatakeColor.surface.raised)
            }
        }

        private var copyCountLabel: String {
            "\(copies.count) \(copies.count == 1 ? "Copy" : "Copies")"
        }
    }
#endif
