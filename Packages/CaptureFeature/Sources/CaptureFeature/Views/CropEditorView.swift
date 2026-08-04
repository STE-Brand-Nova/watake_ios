import DesignSystem
import SwiftUI
import WatakeDomain

public struct CropEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var state: CaptureReviewState
    public let rectifier: (any DocumentRectifying)?

    @State private var topLeft: NormalizedPoint
    @State private var topRight: NormalizedPoint
    @State private var bottomRight: NormalizedPoint
    @State private var bottomLeft: NormalizedPoint

    public init(state: CaptureReviewState, rectifier: (any DocumentRectifying)? = nil) {
        self.state = state
        self.rectifier = rectifier
        let initialQuad = state.selectedPage?.cropQuadrilateral ?? .unit
        _topLeft = State(initialValue: initialQuad.topLeft)
        _topRight = State(initialValue: initialQuad.topRight)
        _bottomRight = State(initialValue: initialQuad.bottomRight)
        _bottomLeft = State(initialValue: initialQuad.bottomLeft)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WatakeSpacing.lg) {
                    if let page = state.selectedPage, let platformImage = PlatformImage(data: page.sourceData) {
                        platformImage.swiftUIImage
                            .resizable()
                            .scaledToFit()
                            .overlay { cornerOverlay }
                            .padding(.horizontal, WatakeSpacing.md)
                    }

                    Text("Drag each corner or enter exact decimal values (0.00 to 1.00) to adjust document boundary.")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WatakeSpacing.lg)

                    cornerControlsSection
                }
                .padding(.vertical, WatakeSpacing.md)
            }
            .background(WatakeColor.surface.base)
            .navigationTitle("Adjust corners")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        state.isEditingCrop = false
                        dismiss()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Cancel crop adjustments")
                }
                ToolbarItem(placement: .confirmationAction) {
                    WatakeButton("Apply", variant: .primary) {
                        let quad = currentQuad
                        guard quad.isValid else { return }
                        state.applyCrop(quadrilateral: quad, via: rectifier)
                        state.isEditingCrop = false
                        dismiss()
                    }
                    .disabled(!currentQuad.isValid)
                    .accessibilityLabel("Apply crop adjustments")
                }
            }
        }
    }

    private var currentQuad: CropQuadrilateral {
        CropQuadrilateral(
            topLeft: topLeft,
            topRight: topRight,
            bottomRight: bottomRight,
            bottomLeft: bottomLeft
        )
    }

    private var cornerOverlay: some View {
        GeometryReader { proxy in
            ForEach(CropCorner.allCases) { corner in
                Circle()
                    .fill(WatakeColor.brand.primary)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(WatakeColor.text.onPrimary, lineWidth: 2))
                    .position(position(for: corner, in: proxy.size))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                update(corner, with: value.location, in: proxy.size)
                            }
                    )
                    .accessibilityLabel("\(corner.label) crop corner")
            }
        }
    }

    private var cornerControlsSection: some View {
        VStack(spacing: WatakeSpacing.md) {
            ForEach(CropCorner.allCases, id: \.self) { corner in
                cornerRow(for: corner)
            }
        }
        .padding(.horizontal, WatakeSpacing.md)
    }

    private func cornerRow(for corner: CropCorner) -> some View {
        let label = corner.label
        let horizontalBinding = binding(for: corner, axis: .horizontal)
        let verticalBinding = binding(for: corner, axis: .vertical)

        return VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
            Text(label)
                .watakeType(.bodyEmphasis)
                .foregroundStyle(WatakeColor.text.primary)

            HStack(spacing: WatakeSpacing.sm) {
                Text("Horizontal")
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
                    .frame(width: 70, alignment: .leading)

                Slider(value: horizontalBinding, in: 0 ... 1)
                    .accessibilityLabel("\(label) horizontal slider")

                TextField("X", value: horizontalBinding, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.plain)
                    .padding(4)
                    .background(WatakeColor.surface.sunken)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
                    .frame(width: 55)
                    .accessibilityLabel("\(label) horizontal position decimal input")
            }

            HStack(spacing: WatakeSpacing.sm) {
                Text("Vertical")
                    .watakeType(.caption)
                    .foregroundStyle(WatakeColor.text.secondary)
                    .frame(width: 70, alignment: .leading)

                Slider(value: verticalBinding, in: 0 ... 1)
                    .accessibilityLabel("\(label) vertical slider")

                TextField("Y", value: verticalBinding, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.plain)
                    .padding(4)
                    .background(WatakeColor.surface.sunken)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
                    .frame(width: 55)
                    .accessibilityLabel("\(label) vertical position decimal input")
            }
        }
        .padding(WatakeSpacing.md)
        .background(WatakeColor.surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md))
    }

    private func position(for corner: CropCorner, in size: CGSize) -> CGPoint {
        let cornerPoint = point(for: corner)
        return CGPoint(x: cornerPoint.x * size.width, y: (1 - cornerPoint.y) * size.height)
    }

    private func update(_ corner: CropCorner, with location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let normalized = NormalizedPoint(
            x: min(1, max(0, Double(location.x / size.width))),
            y: min(1, max(0, Double(1 - location.y / size.height)))
        )
        set(normalized, for: corner)
    }

    private func point(for corner: CropCorner) -> NormalizedPoint {
        switch corner {
        case .topLeft: topLeft
        case .topRight: topRight
        case .bottomRight: bottomRight
        case .bottomLeft: bottomLeft
        }
    }

    private func set(_ point: NormalizedPoint, for corner: CropCorner) {
        switch corner {
        case .topLeft: topLeft = point
        case .topRight: topRight = point
        case .bottomRight: bottomRight = point
        case .bottomLeft: bottomLeft = point
        }
    }

    private func binding(for corner: CropCorner, axis: CropAxis) -> Binding<Double> {
        Binding(
            get: { axis == .horizontal ? point(for: corner).x : point(for: corner).y },
            set: { val in
                var cornerPoint = point(for: corner)
                if axis == .horizontal {
                    cornerPoint.x = min(1.0, max(0.0, val))
                } else {
                    cornerPoint.y = min(1.0, max(0.0, val))
                }
                set(cornerPoint, for: corner)
            }
        )
    }
}

private enum CropCorner: CaseIterable, Identifiable {
    case topLeft, topRight, bottomRight, bottomLeft
    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomRight: "Bottom Right"
        case .bottomLeft: "Bottom Left"
        }
    }
}

private enum CropAxis { case horizontal, vertical }
