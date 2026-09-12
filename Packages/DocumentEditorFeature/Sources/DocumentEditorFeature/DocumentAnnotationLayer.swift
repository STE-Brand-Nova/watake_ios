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
        let showHighlightStyle: (UUID) -> Void
        @State private var adjustsHighlight = false
        @GestureState private var movePreview: AnnotationTransform?
        @GestureState private var resizePreview: AnnotationTransform?
        @GestureState private var rotationPreview: AnnotationTransform?
        @GestureState private var scaleRotationPreview: AnnotationTransform?

        var body: some View {
            ZStack {
                if isSelected, annotation.kind == .highlight, movePreview == nil {
                    HighlightSelectionOutline(
                        strokes: annotation.strokes,
                        pageShortEdge: min(pageSize.width, pageSize.height)
                    )
                    .allowsHitTesting(false)
                }
                content
                    .contentShape(AnnotationHitShape(
                        annotation: annotation,
                        pageShortEdge: min(pageSize.width, pageSize.height)
                    ))
                    .onTapGesture {
                        if isSelected, annotation.kind == .text {
                            editText(annotation.id)
                        } else {
                            model.selectAnnotation(annotation.id)
                        }
                    }
                    .gesture(moveGesture(forceHighlight: false).simultaneously(with: scaleAndRotationGesture))
                if isSelected {
                    if annotation.kind == .text, movePreview == nil {
                        Rectangle()
                            .stroke(WatakeColor.brand.primary, lineWidth: 2)
                            .allowsHitTesting(false)
                        textSelectionControls
                    } else if annotation.kind == .highlight {
                        HighlightContextToolbar(
                            isAdjusting: $adjustsHighlight,
                            appearsBelow: highlightAppearsNearPageTop,
                            moveGesture: moveGesture(forceHighlight: true),
                            delete: {
                                model.selectAnnotation(annotation.id)
                                model.deleteSelected()
                            },
                            showMore: { showHighlightStyle(annotation.id) }
                        )
                    } else if movePreview == nil {
                        Rectangle()
                            .stroke(WatakeColor.brand.primary, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: displayedTransform.width * pageSize.width, height: displayedTransform.height * pageSize.height)
            .rotationEffect(.degrees(displayedTransform.rotation))
            .opacity(annotation.opacity)
            .position(x: displayedTransform.centerX * pageSize.width, y: displayedTransform.centerY * pageSize.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(annotation.kind.rawValue.capitalized) annotation")
            .accessibilityHint(annotationAccessibilityHint(annotation.kind))
            .accessibilityAction(named: "Edit text") {
                guard annotation.kind == .text else { return }
                editText(annotation.id)
            }
            .onChange(of: isSelected) { _, selected in
                if !selected {
                    adjustsHighlight = false
                }
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
                if annotationTextIsClipped(annotation.text, transform: displayedTransform, pageSize: pageSize) {
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

                TextSelectionButton(
                    icon: "xmark",
                    label: "Delete text",
                    role: .destructive,
                    pageShortEdge: min(pageSize.width, pageSize.height)
                ) {
                    model.selectAnnotation(annotation.id)
                    model.deleteSelected()
                }
                .position(x: 0, y: 0)

                TextSelectionButton(
                    icon: "ellipsis",
                    label: "Text style",
                    pageShortEdge: min(pageSize.width, pageSize.height)
                ) {
                    showTextStyle(annotation.id)
                }
                .position(x: proxy.size.width, y: 0)

                TextSelectionButton(
                    icon: "doc.on.doc",
                    label: "Copy text",
                    pageShortEdge: min(pageSize.width, pageSize.height)
                ) {
                    model.selectAnnotation(annotation.id)
                    model.duplicateSelected()
                }
                .position(x: 0, y: proxy.size.height)

                TextSelectionHandle(
                    icon: "arrow.down.right.and.arrow.up.left",
                    label: "Resize text",
                    pageShortEdge: min(pageSize.width, pageSize.height)
                )
                .position(x: proxy.size.width, y: proxy.size.height)
                .gesture(resizeGesture)

                TextSelectionHandle(
                    icon: "rotate.right",
                    label: "Rotate text",
                    pageShortEdge: min(pageSize.width, pageSize.height)
                )
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

        private var highlightAppearsNearPageTop: Bool {
            let top = (displayedTransform.centerY - displayedTransform.height / 2) * pageSize.height
            return top < 56
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
                StrokeCanvas(
                    strokes: annotation.strokes,
                    usesMultiplyBlend: annotation.kind == .highlight,
                    pageShortEdge: min(pageSize.width, pageSize.height)
                )
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

        private func moveGesture(forceHighlight: Bool) -> some Gesture {
            DragGesture(coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .updating($movePreview) { value, preview, _ in
                    guard canTransform(forceHighlight: forceHighlight) else { return }
                    preview = DocumentAnnotationInteraction.moved(
                        from: annotation.transform,
                        translation: value.translation,
                        pageSize: pageSize
                    )
                }
                .onEnded { value in
                    guard canTransform(forceHighlight: forceHighlight) else { return }
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
                        if annotation.kind == .highlight {
                            adjustsHighlight = false
                        }
                    }
                }
        }

        private var scaleAndRotationGesture: some Gesture {
            MagnifyGesture().simultaneously(with: RotateGesture())
                .updating($scaleRotationPreview) { value, preview, _ in
                    guard model.tool == .select,
                          annotation.kind != .text,
                          annotation.kind != .highlight else { return }
                    preview = DocumentAnnotationInteraction.scaledAndRotated(
                        from: annotation.transform,
                        scale: Double(value.first?.magnification ?? 1),
                        rotationDelta: value.second?.rotation.degrees ?? 0
                    )
                }
                .onEnded { value in
                    guard model.tool == .select,
                          annotation.kind != .text,
                          annotation.kind != .highlight else { return }
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

        private func canTransform(forceHighlight: Bool) -> Bool {
            if annotation.kind == .highlight {
                return model.tool == .select && isSelected && (forceHighlight || adjustsHighlight)
            }
            return model.tool == .select || (model.tool == .text && annotation.kind == .text)
        }
    }

    private struct StrokeCanvas: View {
        let strokes: [InkStroke]
        let usesMultiplyBlend: Bool
        let pageShortEdge: CGFloat

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
                            lineWidth: max(1, stroke.width * pageShortEdge),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
    }

    private struct HighlightSelectionOutline: View {
        let strokes: [InkStroke]
        let pageShortEdge: CGFloat

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
                        with: .color(WatakeColor.brand.primary.opacity(0.5)),
                        style: .init(
                            lineWidth: max(3, stroke.width * pageShortEdge + 3),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }
            }
        }
    }

    private struct AnnotationHitShape: Shape {
        let annotation: PageAnnotation
        let pageShortEdge: CGFloat

        func path(in rect: CGRect) -> Path {
            guard annotation.kind == .highlight else { return Path(rect) }
            var result = Path()
            for stroke in annotation.strokes {
                guard let first = stroke.points.first else { continue }
                var centerline = Path()
                centerline.move(to: CGPoint(x: first.location.x * rect.width, y: first.location.y * rect.height))
                for point in stroke.points.dropFirst() {
                    centerline.addLine(to: CGPoint(x: point.location.x * rect.width, y: point.location.y * rect.height))
                }
                result.addPath(centerline.strokedPath(.init(
                    lineWidth: max(44, stroke.width * pageShortEdge + 16),
                    lineCap: .round,
                    lineJoin: .round
                )))
            }
            return result
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

    private func annotationAccessibilityHint(_ kind: PageAnnotationKind) -> String {
        switch kind {
        case .text:
            "Tap to select. Tap selected text again to edit content."
        case .highlight:
            "Tap to select. Use Adjust or Move before dragging."
        case .signature, .image:
            "Tap to select, then drag to reposition."
        }
    }

    private func annotationTextIsClipped(
        _ text: AnnotationText?,
        transform: AnnotationTransform,
        pageSize: CGSize
    ) -> Bool {
        guard let text else { return false }
        let width = transform.width * pageSize.width
        let height = transform.height * pageSize.height
        let bounds = (text.text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: annotationUIFont(text, pageSize: pageSize)],
            context: nil
        )
        return ceil(bounds.height) > height
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
