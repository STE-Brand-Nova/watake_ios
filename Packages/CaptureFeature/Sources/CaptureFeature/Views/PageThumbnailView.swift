import DesignSystem
import SwiftUI
import WatakeDomain

public struct PageThumbnailView: View {
    public let page: CaptureReviewPage
    public let index: Int
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onDelete: (() -> Void)?

    public init(
        page: CaptureReviewPage,
        index: Int,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.page = page
        self.index = index
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(spacing: WatakeSpacing.xs) {
                ZStack(alignment: .topTrailing) {
                    thumbnailImage
                        .frame(width: 72, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: WatakeRadius.sm)
                                .strokeBorder(
                                    isSelected ? WatakeColor.brand.primary : WatakeColor.border.subtle,
                                    lineWidth: isSelected ? 3 : 1
                                )
                        )
                        .shadow(
                            color: isSelected ? WatakeColor.brand.primary.opacity(0.3) : .clear,
                            radius: 4
                        )

                    if page.rotationDegrees != 0 {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WatakeColor.text.onPrimary)
                            .padding(4)
                            .background(WatakeColor.brand.primary)
                            .clipShape(Circle())
                            .offset(x: -4, y: 4)
                    }

                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(WatakeColor.text.onPrimary)
                                .padding(6)
                                .background(WatakeColor.status.danger)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Delete page \(index + 1)")
                    }
                }

                Text("Page \(index + 1)")
                    .watakeType(.caption)
                    .foregroundStyle(isSelected ? WatakeColor.text.primary : WatakeColor.text.secondary)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let rotationInfo = page.rotationDegrees != 0 ? ", rotated \(page.rotationDegrees) degrees" : ""
        let selectionInfo = isSelected ? ", selected" : ""
        return "Page \(index + 1)\(selectionInfo)\(rotationInfo)"
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let platformImage = PlatformImage(data: page.displayData) {
            platformImage.swiftUIImage
                .resizable()
                .scaledToFill()
                .rotationEffect(.degrees(page.visualRotationDegrees))
        } else {
            Rectangle()
                .fill(WatakeColor.surface.sunken)
                .overlay(
                    Image(systemName: "doc")
                        .foregroundStyle(WatakeColor.text.secondary)
                )
        }
    }
}
