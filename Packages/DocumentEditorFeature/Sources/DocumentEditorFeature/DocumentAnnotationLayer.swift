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
        @GestureState private var movePreview: AnnotationTransform?
        @GestureState private var resizePreview: AnnotationTransform?
        @GestureState private var rotationPreview: AnnotationTransform?
        @GestureState private var scaleRotationPreview: AnnotationTransform?

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
                if isSelected, movePreview == nil {
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
            rotationPreview ?? resizePreview ?? scaleRotationPreview ?? movePreview ?? annotation.transform
        }

        private var textSelectionControls: some View {
            GeometryReader { proxy in
                if textIsClipped {
                    Label("Text clipped", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatakeColor.status.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(WatakeColor.surface.raised.opacity(0.92))
                        .clipShape(Capsule())
                        .position(x: proxy.size.width / 2, y: min(18, proxy.size.height / 2))
                        .allowsHitTesting(false)
                        .accessibilityLabel("Text is clipped. Enlarge the box or reduce the font size.")
                }

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

                selectionHandle(icon: "rotate.right", label: "Rotate text")
                    .position(x: proxy.size.width / 2, y: proxy.size.height)
                    .gesture(rotationGesture)
                    .accessibilityAction(named: "Rotate clockwise") {
                        rotateSelected(by: 15)
                    }
                    .accessibilityAction(named: "Rotate counterclockwise") {
                        rotateSelected(by: -15)
                    }
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
                .updating($resizePreview) { value, preview, _ in
                    preview = DocumentAnnotationInteraction.resized(
                        from: annotation.transform,
                        translation: value.translation,
                        pageSize: pageSize
                    )
                }
                .onEnded { value in
                    let transform = DocumentAnnotationInteraction.resized(
                        from: annotation.transform,
                        translation: value.translation,
                        pageSize: pageSize
                    )
                    if transform != annotation.transform {
                        model.selectAnnotation(annotation.id)
                        model.transformSelected(
                            centerX: transform.centerX,
                            centerY: transform.centerY,
                            width: transform.width,
                            height: transform.height
                        )
                    }
                }
        }

        private var rotationGesture: some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .updating($rotationPreview) { value, preview, _ in
                    preview = DocumentAnnotationInteraction.rotated(
                        from: annotation.transform,
                        startLocation: value.startLocation,
                        location: value.location,
                        pageSize: pageSize
                    )
                }
                .onEnded { value in
                    let transform = DocumentAnnotationInteraction.rotated(
                        from: annotation.transform,
                        startLocation: value.startLocation,
                        location: value.location,
                        pageSize: pageSize
                    )
                    if transform != annotation.transform {
                        model.selectAnnotation(annotation.id)
                        model.transformSelected(rotationDelta: transform.rotation - annotation.transform.rotation)
                    }
                }
        }

        private func rotateSelected(by degrees: Double) {
            model.selectAnnotation(annotation.id)
            model.transformSelected(rotationDelta: degrees)
        }

        @ViewBuilder private var content: some View {
            switch annotation.kind {
            case .text:
                if let text = annotation.text {
                    Text(text.text)
                        .font(annotationFont(text, pageSize: pageSize))
                        .underline(text.isUnderlined)
                        .foregroundStyle(annotationContentColor(text.colorHex))
                        .multilineTextAlignment(annotationTextAlignment(text.alignment))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: annotationFrameAlignment(text.alignment))
                        .clipped()
                }
            case .signature, .highlight:
                StrokeCanvas(strokes: annotation.strokes, usesMultiplyBlend: annotation.kind == .highlight)
            case .image:
                if let reference = annotation.image, let data = model.annotationImages[reference.id] {
                    AnnotationImageContent(
                        id: reference.id,
                        data: data,
                        targetSize: pageSize
                    )
                }
            }
        }

        private var moveGesture: some Gesture {
            DragGesture(coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .updating($movePreview) { value, preview, _ in
                    guard canTransform else { return }
                    preview = DocumentAnnotationInteraction.moved(
                        from: annotation.transform,
                        translation: value.translation,
                        pageSize: pageSize
                    )
                }
                .onEnded { value in
                    guard canTransform else { return }
                    let transform = DocumentAnnotationInteraction.moved(
                        from: annotation.transform,
                        translation: value.translation,
                        pageSize: pageSize
                    )
                    if transform != annotation.transform {
                        model.selectAnnotation(annotation.id)
                        model.transformSelected(
                            centerX: transform.centerX,
                            centerY: transform.centerY
                        )
                    }
                }
                .simultaneously(with: scaleAndRotationGesture)
        }

        private var scaleAndRotationGesture: some Gesture {
            MagnifyGesture().simultaneously(with: RotateGesture())
                .updating($scaleRotationPreview) { value, preview, _ in
                    guard model.tool == .select, annotation.kind != .text else { return }
                    preview = DocumentAnnotationInteraction.scaledAndRotated(
                        from: annotation.transform,
                        scale: Double(value.first?.magnification ?? 1),
                        rotationDelta: value.second?.rotation.degrees ?? 0
                    )
                }
                .onEnded { value in
                    guard model.tool == .select, annotation.kind != .text else { return }
                    let transform = DocumentAnnotationInteraction.scaledAndRotated(
                        from: annotation.transform,
                        scale: Double(value.first?.magnification ?? 1),
                        rotationDelta: value.second?.rotation.degrees ?? 0
                    )
                    if transform != annotation.transform {
                        model.selectAnnotation(annotation.id)
                        model.transformSelected(
                            width: transform.width,
                            height: transform.height,
                            rotationDelta: transform.rotation - annotation.transform.rotation
                        )
                    }
                }
        }

        private var canTransform: Bool {
            model.tool == .select || (model.tool == .text && annotation.kind == .text)
        }

        private var textIsClipped: Bool {
            guard let text = annotation.text else { return false }
            let width = displayedTransform.width * pageSize.width
            let height = displayedTransform.height * pageSize.height
            let bounds = (text.text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: annotationUIFont(text, pageSize: pageSize)],
                context: nil
            )
            return ceil(bounds.height) > height
        }
    }

    private struct StrokeCanvas: View {
        let strokes: [InkStroke]
        let usesMultiplyBlend: Bool

        var body: some View {
            Canvas { context, size in
                if usesMultiplyBlend {
                    context.blendMode = .multiply
                }
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

    private struct AnnotationImageContent: View {
        let id: UUID
        let data: Data
        let targetSize: CGSize
        @State private var image: UIImage?
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .task(id: id) {
                guard let source = UIImage(data: data) else { return }
                let preparedSize = CGSize(width: targetSize.width * displayScale, height: targetSize.height * displayScale)
                image = await source.byPreparingThumbnail(ofSize: preparedSize) ?? source
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
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }

    private func annotationFont(_ text: AnnotationText, pageSize: CGSize) -> Font {
        Font(annotationUIFont(text, pageSize: pageSize))
    }

    private func annotationUIFont(_ text: AnnotationText, pageSize: CGSize) -> UIFont {
        let size = text.fontSize * min(pageSize.width, pageSize.height)
        let base = UIFont(name: text.fontName, size: size) ?? UIFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        var traits = base.fontDescriptor.symbolicTraits
        if text.isBold {
            traits.insert(.traitBold)
        }
        if text.isItalic {
            traits.insert(.traitItalic)
        }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
#endif
