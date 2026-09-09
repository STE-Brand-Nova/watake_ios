#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    struct AnnotationLayer: View {
        @Bindable var model: DocumentEditorModel
        let annotation: PageAnnotation
        let pageSize: CGSize
        let editText: (UUID) -> Void
        let showTextStyle: (UUID) -> Void
        @State private var dragStart: AnnotationTransform?
        @State private var resizeStart: AnnotationTransform?
        @State private var interactionTransform: AnnotationTransform?
        @State private var lastScale = 1.0
        @State private var lastRotation = Angle.zero

        var body: some View {
            ZStack {
                content
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelected, annotation.kind == .text {
                            editText(annotation.id)
                        } else {
                            model.selectAnnotation(annotation.id)
                        }
                    }
                    .gesture(moveGesture)
                if isSelected, dragStart == nil {
                    Rectangle()
                        .stroke(WatakeColor.brand.primary, lineWidth: 2)
                        .allowsHitTesting(false)
                    if annotation.kind == .text {
                        textSelectionControls
                    }
                }
            }
            .frame(width: displayedTransform.width * pageSize.width, height: displayedTransform.height * pageSize.height)
            .rotationEffect(.degrees(displayedTransform.rotation))
            .opacity(annotation.opacity)
            .position(x: displayedTransform.centerX * pageSize.width, y: displayedTransform.centerY * pageSize.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(annotation.kind.rawValue.capitalized) annotation")
            .accessibilityHint("Tap to select. Tap selected text again to edit content.")
            .accessibilityAction(named: "Edit text") {
                guard annotation.kind == .text else { return }
                editText(annotation.id)
            }
        }

        private var isSelected: Bool {
            model.selectedAnnotationID == annotation.id
        }

        private var displayedTransform: AnnotationTransform {
            interactionTransform ?? annotation.transform
        }

        private var textSelectionControls: some View {
            GeometryReader { proxy in
                selectionButton(icon: "xmark", label: "Delete text", role: .destructive) {
                    model.selectAnnotation(annotation.id)
                    model.deleteSelected()
                }
                .position(x: 0, y: 0)

                selectionButton(icon: "ellipsis", label: "Text style") {
                    showTextStyle(annotation.id)
                }
                .position(x: proxy.size.width, y: 0)

                selectionButton(icon: "doc.on.doc", label: "Copy text") {
                    model.selectAnnotation(annotation.id)
                    model.duplicateSelected()
                }
                .position(x: 0, y: proxy.size.height)

                selectionHandle(icon: "arrow.down.right.and.arrow.up.left", label: "Resize text")
                    .position(x: proxy.size.width, y: proxy.size.height)
                    .gesture(resizeGesture)
            }
        }

        private func selectionButton(
            icon: String,
            label: String,
            role: ButtonRole? = nil,
            action: @escaping () -> Void
        ) -> some View {
            Button(role: role, action: action) {
                selectionControl(icon: icon, role: role)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }

        private func selectionHandle(icon: String, label: String) -> some View {
            selectionControl(icon: icon)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        }

        private func selectionControl(icon: String, role: ButtonRole? = nil) -> some View {
            let diameter = min(max(min(pageSize.width, pageSize.height) * 0.075, 26), 32)
            return Image(systemName: icon)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .frame(width: diameter, height: diameter)
                .foregroundStyle(role == .destructive ? WatakeColor.status.danger : WatakeColor.brand.primary)
                .background(WatakeColor.surface.raised)
                .clipShape(Circle())
                .overlay(Circle().stroke(WatakeColor.border.strong, lineWidth: 1))
        }

        private var resizeGesture: some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .onChanged { value in
                    if resizeStart == nil {
                        model.selectAnnotation(annotation.id)
                        resizeStart = annotation.transform
                    }
                    guard let start = resizeStart else { return }
                    interactionTransform = DocumentAnnotationInteraction.resized(
                        from: start,
                        translation: value.translation,
                        pageSize: pageSize
                    )
                }
                .onEnded { _ in
                    guard let transform = interactionTransform, resizeStart != nil else { return }
                    model.selectAnnotation(annotation.id)
                    model.transformSelected(
                        centerX: transform.centerX,
                        centerY: transform.centerY,
                        width: transform.width,
                        height: transform.height
                    )
                    resizeStart = nil
                    interactionTransform = nil
                }
        }

        @ViewBuilder private var content: some View {
            switch annotation.kind {
            case .text:
                if let text = annotation.text {
                    Text(text.text)
                        .font(.custom(text.fontName, size: max(10, text.fontSize * min(pageSize.width, pageSize.height))))
                        .fontWeight(text.isBold ? .bold : .regular)
                        .italic(text.isItalic)
                        .underline(text.isUnderlined)
                        .foregroundStyle(annotationContentColor(text.colorHex))
                        .multilineTextAlignment(annotationTextAlignment(text.alignment))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: annotationFrameAlignment(text.alignment))
                }
            case .signature, .highlight:
                StrokeCanvas(strokes: annotation.strokes)
            case .image:
                if let reference = annotation.image,
                   let data = model.annotationImages[reference.id],
                   let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
        }

        private var moveGesture: some Gesture {
            DragGesture(coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .onChanged { value in
                    guard canTransform else { return }
                    if dragStart == nil {
                        model.selectAnnotation(annotation.id)
                        dragStart = annotation.transform
                        if annotation.kind != .text {
                            model.beginContinuousEdit()
                        }
                    }
                    guard let start = dragStart else { return }
                    if annotation.kind == .text {
                        interactionTransform = DocumentAnnotationInteraction.moved(
                            from: start,
                            translation: value.translation,
                            pageSize: pageSize
                        )
                    } else {
                        model.transformSelected(
                            centerX: start.centerX + value.translation.width / pageSize.width,
                            centerY: start.centerY + value.translation.height / pageSize.height
                        )
                    }
                }
                .onEnded { _ in
                    guard dragStart != nil else { return }
                    if annotation.kind == .text, let transform = interactionTransform {
                        model.selectAnnotation(annotation.id)
                        model.transformSelected(centerX: transform.centerX, centerY: transform.centerY)
                    } else if annotation.kind != .text {
                        model.endContinuousEdit()
                    }
                    dragStart = nil
                    interactionTransform = nil
                }
                .simultaneously(with: scaleAndRotationGesture)
        }

        private var scaleAndRotationGesture: some Gesture {
            let scale = MagnifyGesture().onChanged { value in
                guard model.tool == .select, annotation.kind != .text else { return }
                if lastScale == 1 {
                    model.selectAnnotation(annotation.id)
                    model.beginContinuousEdit()
                }
                model.transformSelected(scale: value.magnification / lastScale)
                lastScale = value.magnification
            }.onEnded { _ in
                guard lastScale != 1 else { return }
                lastScale = 1
                model.endContinuousEdit()
            }
            let rotate = RotateGesture().onChanged { value in
                guard model.tool == .select, annotation.kind != .text else { return }
                if lastRotation == .zero {
                    model.selectAnnotation(annotation.id)
                    model.beginContinuousEdit()
                }
                model.transformSelected(rotationDelta: value.rotation.degrees - lastRotation.degrees)
                lastRotation = value.rotation
            }.onEnded { _ in
                guard lastRotation != .zero else { return }
                lastRotation = .zero
                model.endContinuousEdit()
            }
            return scale.simultaneously(with: rotate)
        }

        private var canTransform: Bool {
            model.tool == .select || (model.tool == .text && annotation.kind == .text)
        }
    }

    private struct StrokeCanvas: View {
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
                        with: .color(annotationContentColor(stroke.colorHex).opacity(stroke.opacity)),
                        style: .init(
                            lineWidth: max(1, stroke.width * min(size.width, size.height)),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
    }

    private func annotationContentColor(_ hex: String) -> Color {
        guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return WatakeColor.text.primary }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private func annotationTextAlignment(_ alignment: AnnotationTextAlignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func annotationFrameAlignment(_ alignment: AnnotationTextAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
#endif
