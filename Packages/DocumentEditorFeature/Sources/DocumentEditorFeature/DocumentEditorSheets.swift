#if canImport(UIKit)
    import DesignSystem
    import PencilKit
    import SwiftUI
    import WatakeDomain

    struct SaveCopySheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        @State private var name = ""
        @State private var folderID: UUID?

        var body: some View {
            NavigationStack {
                Form {
                    TextField("Document name", text: $name)
                    Picker("Folder", selection: $folderID) {
                        ForEach(model.folders) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                .navigationTitle("Save a Copy")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let folderID else { return }
                            Task {
                                if await model.saveCopy(name: name, folderID: folderID) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || folderID == nil)
                    }
                }
                .onAppear {
                    name = "\(model.document.name) – Copy"
                    folderID = model.document.folderId
                }
            }
            .presentationDetents([.medium])
        }
    }

    struct PageTargetsSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        @State private var selected: Set<UUID> = []

        var body: some View {
            NavigationStack {
                List(model.pages) { page in
                    Button {
                        if selected.contains(page.id) {
                            selected.remove(page.id)
                        } else {
                            selected.insert(page.id)
                        }
                    } label: {
                        HStack {
                            Text("Page \(page.index + 1)")
                            Spacer()
                            if selected.contains(page.id) {
                                Image(systemName: "checkmark").foregroundStyle(WatakeColor.brand.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Duplicate to Pages")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Duplicate") {
                            model.duplicateSelected(to: selected)
                            dismiss()
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
        }
    }

    struct SignatureSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        @State private var drawing = PKDrawing()
        @State private var name = ""
        @State private var savesForReuse = false
        @State private var inkColor = "#0B1220"

        var body: some View {
            NavigationStack {
                VStack(spacing: WatakeSpacing.md) {
                    if !model.signatures.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(model.signatures) { signature in
                                    Button(signature.name) {
                                        model.applySignature(signature)
                                        dismiss()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.horizontal, WatakeSpacing.md)
                        }
                    }
                    PencilSignatureCanvas(drawing: $drawing, colorHex: inkColor)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: WatakeRadius.md).stroke(WatakeColor.border.strong))
                        .padding(.horizontal, WatakeSpacing.md)
                    HStack {
                        Button("Black") { inkColor = "#0B1220" }
                        Button("Blue") { inkColor = "#1F4FEB" }
                        Spacer()
                        Button("Clear") { drawing = PKDrawing() }
                    }
                    .padding(.horizontal, WatakeSpacing.md)
                    Toggle("Save to My Signatures", isOn: $savesForReuse)
                        .padding(.horizontal, WatakeSpacing.md)
                    if savesForReuse {
                        TextField("Signature name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, WatakeSpacing.md)
                    }
                }
                .padding(.vertical, WatakeSpacing.md)
                .navigationTitle("Add Signature")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let strokes = normalizedSignatureStrokes(drawing, colorHex: inkColor)
                            guard !strokes.isEmpty else { return }
                            model.addSignature(strokes: strokes)
                            if savesForReuse {
                                Task { _ = await model.saveSignature(name: name, strokes: strokes) }
                            }
                            dismiss()
                        }
                        .disabled(
                            drawing.strokes.isEmpty ||
                                (savesForReuse && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        )
                    }
                }
            }
        }
    }

    private struct PencilSignatureCanvas: UIViewRepresentable {
        @Binding var drawing: PKDrawing
        let colorHex: String

        func makeCoordinator() -> Coordinator {
            Coordinator(drawing: $drawing)
        }

        func makeUIView(context: Context) -> PKCanvasView {
            let view = PKCanvasView()
            view.delegate = context.coordinator
            view.drawingPolicy = .anyInput
            view.backgroundColor = .white
            view.tool = PKInkingTool(.pen, color: signatureUIColor(colorHex), width: 4)
            return view
        }

        func updateUIView(_ view: PKCanvasView, context _: Context) {
            if view.drawing != drawing {
                view.drawing = drawing
            }
            view.tool = PKInkingTool(.pen, color: signatureUIColor(colorHex), width: 4)
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

    private func normalizedSignatureStrokes(_ drawing: PKDrawing, colorHex: String) -> [InkStroke] {
        let bounds = drawing.bounds
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        return drawing.strokes.compactMap { stroke in
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
#endif
