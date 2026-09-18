#if canImport(UIKit)
    import DesignSystem
    import PencilKit
    import SwiftUI
    import WatakeDomain

    struct SignatureSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        @State private var tab = SignaturePanelTab.draw
        @State private var drawing = PKDrawing()
        @State private var boardStyle = SignatureBoardStyle.whiteboard
        @State private var inkColor = "#0B1220"
        @State private var thickness = SignatureStrokeThickness.medium
        @State private var savesForReuse = false
        @State private var name = ""
        @State private var selectedSavedID: UUID?
        @State private var savedInkColor = "#0B1220"

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Signature source", selection: $tab) {
                        ForEach(SignaturePanelTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, WatakeSpacing.md)
                    .padding(.top, WatakeSpacing.sm)

                    ScrollView {
                        if tab == .draw {
                            drawPanel
                        } else {
                            savedPanel
                        }
                    }
                }
                .navigationTitle("Add Signature")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Use signature", action: useSignature)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(!canUseSignature)
                        .padding(.horizontal, WatakeSpacing.md)
                        .padding(.vertical, WatakeSpacing.sm)
                        .background(WatakeColor.surface.raised)
                        .overlay(alignment: .top) { Divider() }
                }
                .onAppear {
                    selectedSavedID = selectedSavedID ?? model.signatures.first?.id
                }
                .onChange(of: inkColor) { _, colorHex in
                    drawing = recoloredSignatureDrawing(drawing, colorHex: colorHex)
                }
            }
            .presentationDetents([.large])
        }

        private var drawPanel: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.md) {
                Picker("Drawing board", selection: $boardStyle) {
                    ForEach(SignatureBoardStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                PencilSignatureCanvas(
                    drawing: $drawing,
                    colorHex: inkColor,
                    strokeWidth: thickness.width,
                    boardStyle: boardStyle
                )
                .frame(minHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md))
                .overlay(RoundedRectangle(cornerRadius: WatakeRadius.md).stroke(WatakeColor.border.strong))
                .accessibilityLabel("Signature drawing board")

                signatureColorControl(title: "Ink color", colorHex: $inkColor)

                VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                    Text("Stroke thickness").watakeType(.caption)
                    Picker("Stroke thickness", selection: $thickness) {
                        ForEach(SignatureStrokeThickness.allCases) { thickness in
                            Text(thickness.title).tag(thickness)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Button {
                        drawing = PKDrawing(strokes: Array(drawing.strokes.dropLast()))
                    } label: {
                        Label("Undo stroke", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(drawing.strokes.isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        drawing = PKDrawing()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(drawing.strokes.isEmpty)
                }
                .buttonStyle(.bordered)

                Toggle("Save for reuse", isOn: $savesForReuse)
                if savesForReuse {
                    TextField("Signature name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal, WatakeSpacing.xl)
            .padding(.vertical, WatakeSpacing.md)
        }

        private var savedPanel: some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.md) {
                if model.signatures.isEmpty {
                    ContentUnavailableView(
                        "No Saved Signatures",
                        systemImage: "signature",
                        description: Text("Draw a signature and enable Save for reuse.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    VStack(spacing: WatakeSpacing.sm) {
                        ForEach(model.signatures) { signature in
                            savedSignatureRow(signature)
                        }
                    }
                    signatureColorControl(title: "Color for next copy", colorHex: $savedInkColor)
                }
            }
            .padding(WatakeSpacing.md)
        }

        private func savedSignatureRow(_ signature: SavedSignature) -> some View {
            HStack(spacing: WatakeSpacing.sm) {
                Button {
                    selectedSavedID = signature.id
                } label: {
                    VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                        SignatureStrokeCanvas(
                            strokes: recoloredSignatureStrokes(signature.strokes, colorHex: savedInkColor)
                        )
                        .frame(height: 72)
                        .background(WatakeColor.surface.signaturePreview)
                        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
                        Text(signature.name)
                            .watakeType(.bodyEmphasis)
                            .foregroundStyle(WatakeColor.text.primary)
                    }
                    .padding(WatakeSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WatakeColor.surface.base)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: WatakeRadius.md)
                            .stroke(
                                selectedSavedID == signature.id
                                    ? WatakeColor.brand.primary : WatakeColor.border.subtle,
                                lineWidth: selectedSavedID == signature.id ? 2 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use saved signature \(signature.name)")

                Button(role: .destructive) {
                    Task {
                        if await model.deleteSavedSignature(id: signature.id), selectedSavedID == signature.id {
                            selectedSavedID = model.signatures.first?.id
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Delete saved signature \(signature.name)")
            }
        }

        private func signatureColorControl(title: String, colorHex: Binding<String>) -> some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text(title).watakeType(.caption)
                HStack(spacing: WatakeSpacing.xs) {
                    ForEach(DocumentEditorPalette.signatureColors, id: \.self) { hex in
                        Button {
                            colorHex.wrappedValue = hex
                        } label: {
                            Circle()
                                .fill(signatureColor(hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(
                                    colorHex.wrappedValue == hex
                                        ? WatakeColor.brand.primary : WatakeColor.border.strong,
                                    lineWidth: 2
                                ))
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Choose \(DocumentEditorPalette.colorName(for: hex).lowercased()) ink")
                    }
                    ColorPicker(
                        "Custom ink color",
                        selection: Binding(
                            get: { signatureColor(colorHex.wrappedValue) },
                            set: { colorHex.wrappedValue = signatureHexColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }

        private var canUseSignature: Bool {
            switch tab {
            case .draw:
                !drawing.strokes.isEmpty &&
                    (!savesForReuse || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .saved:
                selectedSavedID != nil
            }
        }

        private func useSignature() {
            switch tab {
            case .draw:
                guard let draft = normalizedSignatureDraft(drawing, colorHex: inkColor),
                      model.prepareSignaturePlacement(strokes: draft.strokes, aspectRatio: draft.aspectRatio) else {
                    return
                }
                if savesForReuse {
                    let signatureName = name
                    Task {
                        _ = await model.saveSignature(
                            name: signatureName,
                            strokes: draft.strokes,
                            aspectRatio: draft.aspectRatio
                        )
                    }
                }
                dismiss()
            case .saved:
                guard let signature = model.signatures.first(where: { $0.id == selectedSavedID }) else { return }
                let strokes = recoloredSignatureStrokes(signature.strokes, colorHex: savedInkColor)
                guard model.prepareSignaturePlacement(strokes: strokes, aspectRatio: signature.aspectRatio) else { return }
                dismiss()
            }
        }
    }

    struct SignatureColorSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        @State private var colorHex: String

        init(model: DocumentEditorModel) {
            self.model = model
            _colorHex = State(initialValue: model.selectedAnnotation?.strokes.first?.colorHex ?? "#0B1220")
        }

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: WatakeSpacing.md) {
                    Text("Signature color").watakeType(.title2)
                    HStack(spacing: WatakeSpacing.sm) {
                        ForEach(DocumentEditorPalette.signatureColors, id: \.self) { hex in
                            Button {
                                colorHex = hex
                                model.updateSelectedSignatureColor(hex)
                            } label: {
                                Circle()
                                    .fill(signatureColor(hex))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(
                                        colorHex == hex ? WatakeColor.brand.primary : WatakeColor.border.strong,
                                        lineWidth: 2
                                    ))
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        ColorPicker(
                            "Custom signature color",
                            selection: Binding(
                                get: { signatureColor(colorHex) },
                                set: {
                                    colorHex = signatureHexColor($0)
                                    model.updateSelectedSignatureColor(colorHex)
                                }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    Spacer()
                }
                .padding(WatakeSpacing.md)
                .navigationTitle("Signature Color")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .presentationDetents([.medium])
        }
    }

    struct SignatureStrokeCanvas: View {
        let strokes: [InkStroke]

        var body: some View {
            Canvas { context, size in
                for stroke in strokes {
                    guard let first = stroke.points.first else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: first.location.x * size.width, y: first.location.y * size.height))
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.location.x * size.width, y: point.location.y * size.height))
                    }
                    context.stroke(
                        path,
                        with: .color(signatureColor(stroke.colorHex).opacity(stroke.opacity)),
                        style: StrokeStyle(
                            lineWidth: max(1, stroke.width * min(size.width, size.height)),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
    }

    private struct PencilSignatureCanvas: UIViewRepresentable {
        @Binding var drawing: PKDrawing
        let colorHex: String
        let strokeWidth: CGFloat
        let boardStyle: SignatureBoardStyle

        func makeCoordinator() -> Coordinator {
            Coordinator(drawing: $drawing)
        }

        func makeUIView(context: Context) -> PKCanvasView {
            let view = PKCanvasView()
            view.delegate = context.coordinator
            view.drawingPolicy = .anyInput
            view.isOpaque = true
            view.overrideUserInterfaceStyle = .light
            configure(view)
            return view
        }

        func updateUIView(_ view: PKCanvasView, context _: Context) {
            if view.drawing != drawing {
                view.drawing = drawing
            }
            configure(view)
        }

        private func configure(_ view: PKCanvasView) {
            view.backgroundColor = boardStyle == .whiteboard ? .white : .black
            view.tool = PKInkingTool(.pen, color: signatureUIColor(colorHex), width: strokeWidth)
        }

        final class Coordinator: NSObject, PKCanvasViewDelegate {
            @Binding var drawing: PKDrawing

            init(drawing: Binding<PKDrawing>) {
                _drawing = drawing
            }

            func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
                drawing = canvasView.drawing
            }
        }
    }

    private enum SignaturePanelTab: String, CaseIterable, Identifiable {
        case draw
        case saved

        var id: String {
            rawValue
        }

        var title: String {
            rawValue.capitalized
        }
    }

    private enum SignatureBoardStyle: String, CaseIterable, Identifiable {
        case whiteboard
        case blackboard

        var id: String {
            rawValue
        }

        var title: String {
            rawValue.capitalized
        }
    }

    private enum SignatureStrokeThickness: String, CaseIterable, Identifiable {
        case thin
        case medium
        case thick

        var id: String {
            rawValue
        }

        var title: String {
            rawValue.capitalized
        }

        var width: CGFloat {
            switch self {
            case .thin: 2
            case .medium: 4
            case .thick: 7
            }
        }
    }

    private struct NormalizedSignatureDraft {
        let strokes: [InkStroke]
        let aspectRatio: Double
    }

    private func normalizedSignatureDraft(_ drawing: PKDrawing, colorHex: String) -> NormalizedSignatureDraft? {
        let bounds = drawing.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let strokes: [InkStroke] = drawing.strokes.compactMap { stroke -> InkStroke? in
            let points = stroke.path.map { point in
                InkPoint(
                    location: NormalizedPoint(
                        x: min(max((point.location.x - bounds.minX) / bounds.width, 0), 1),
                        y: min(max((point.location.y - bounds.minY) / bounds.height, 0), 1)
                    ),
                    pressure: min(max(Double(point.force), 0.2), 1)
                )
            }
            guard points.count >= 2 else { return nil }
            let shortestEdge = Double(min(bounds.width, bounds.height))
            let width = max(0.003, min(0.08, Double(stroke.path.first?.size.width ?? 4) / shortestEdge))
            return InkStroke(points: points, width: width, colorHex: colorHex)
        }
        guard !strokes.isEmpty else { return nil }
        return NormalizedSignatureDraft(
            strokes: strokes,
            aspectRatio: min(max(Double(bounds.width / bounds.height), 0.02), 50)
        )
    }

    func recoloredSignatureStrokes(_ strokes: [InkStroke], colorHex: String) -> [InkStroke] {
        strokes.map {
            InkStroke(points: $0.points, width: $0.width, colorHex: colorHex, opacity: $0.opacity)
        }
    }

    private func recoloredSignatureDrawing(_ drawing: PKDrawing, colorHex: String) -> PKDrawing {
        let ink = PKInk(.pen, color: signatureUIColor(colorHex))
        return PKDrawing(strokes: drawing.strokes.map {
            PKStroke(ink: ink, path: $0.path, transform: $0.transform, mask: $0.mask)
        })
    }

    func signatureColor(_ hex: String) -> Color {
        Color(uiColor: signatureUIColor(hex))
    }

    private func signatureUIColor(_ hex: String) -> UIColor {
        guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return .label }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func signatureHexColor(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if !uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil) {
            var white: CGFloat = 0
            guard uiColor.getWhite(&white, alpha: nil) else { return "#0B1220" }
            red = white
            green = white
            blue = white
        }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
#endif
