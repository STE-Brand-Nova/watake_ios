#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    struct SignatureAnnotationLayer: View {
        @Bindable var model: DocumentEditorModel
        let annotation: PageAnnotation
        let pageSize: CGSize
        let showColor: (UUID) -> Void
        let showResize: (UUID) -> Void
        @GestureState private var movePreview: AnnotationTransform?
        @GestureState private var resizePreview: AnnotationTransform?

        var body: some View {
            ZStack {
                SignatureStrokeCanvas(strokes: annotation.strokes)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectAnnotation(annotation.id) }
                    .gesture(moveGesture)
                if isSelected {
                    Rectangle()
                        .stroke(WatakeColor.brand.primary, lineWidth: 2)
                        .allowsHitTesting(false)
                    selectionControls
                }
            }
            .frame(width: displayedTransform.width * pageSize.width, height: displayedTransform.height * pageSize.height)
            .rotationEffect(.degrees(displayedTransform.rotation))
            .opacity(annotation.opacity)
            .position(x: displayedTransform.centerX * pageSize.width, y: displayedTransform.centerY * pageSize.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Signature annotation")
            .accessibilityHint("Tap to select or drag to reposition.")
            .accessibilityAction(named: "Move left") { moveAccessible(horizontal: -0.02, vertical: 0) }
            .accessibilityAction(named: "Move right") { moveAccessible(horizontal: 0.02, vertical: 0) }
            .accessibilityAction(named: "Move up") { moveAccessible(horizontal: 0, vertical: -0.02) }
            .accessibilityAction(named: "Move down") { moveAccessible(horizontal: 0, vertical: 0.02) }
            .accessibilityAction(named: "Increase size") { resizeAccessible(by: 1.1) }
            .accessibilityAction(named: "Decrease size") { resizeAccessible(by: 0.9) }
        }

        private var isSelected: Bool {
            model.selectedAnnotationID == annotation.id
        }

        private var displayedTransform: AnnotationTransform {
            resizePreview ?? movePreview ?? annotation.transform
        }

        private var usesCompactControls: Bool {
            SignatureSelectionPolicy.usesCompactControls(transform: annotation.transform, pageSize: pageSize)
        }

        private var selectionControls: some View {
            GeometryReader { proxy in
                if !usesCompactControls {
                    selectionHandle(.topLeading, horizontalPosition: 22, verticalPosition: 22)
                    selectionHandle(.topTrailing, horizontalPosition: proxy.size.width - 22, verticalPosition: 22)
                    selectionHandle(.bottomLeading, horizontalPosition: 22, verticalPosition: proxy.size.height - 22)
                    selectionHandle(
                        .bottomTrailing,
                        horizontalPosition: proxy.size.width - 22,
                        verticalPosition: proxy.size.height - 22
                    )
                }

                SignatureContextToolbar(
                    rotation: displayedTransform.rotation,
                    usesCompactControls: usesCompactControls,
                    moveGesture: moveGesture,
                    delete: {
                        model.selectAnnotation(annotation.id)
                        model.deleteSelected()
                    },
                    duplicate: {
                        model.selectAnnotation(annotation.id)
                        model.duplicateSelected()
                    },
                    showColor: { showColor(annotation.id) },
                    showResize: { showResize(annotation.id) }
                )
                .position(x: proxy.size.width / 2, y: toolbarVerticalPosition(in: proxy.size))
            }
        }

        private func selectionHandle(
            _ corner: ImageResizeCorner,
            horizontalPosition: CGFloat,
            verticalPosition: CGFloat
        ) -> some View {
            ImageSelectionHandle(
                label: "Resize signature from \(corner.accessibilityName) corner",
                corner: corner,
                resize: resizeAccessible
            )
            .position(x: horizontalPosition, y: verticalPosition)
            .gesture(resizeGesture(corner))
        }

        private func toolbarVerticalPosition(in size: CGSize) -> CGFloat {
            let top = (displayedTransform.centerY - displayedTransform.height / 2) * pageSize.height
            let bottom = (displayedTransform.centerY + displayedTransform.height / 2) * pageSize.height
            if bottom <= pageSize.height - 64 {
                return size.height + 34
            }
            if top >= 64 {
                return -34
            }
            return max(34, size.height - 34)
        }

        private var moveGesture: some Gesture {
            DragGesture(minimumDistance: 8, coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .updating($movePreview) { value, preview, _ in
                    guard model.tool == .select else { return }
                    preview = DocumentAnnotationInteraction.moved(
                        from: annotation.transform,
                        translation: value.translation,
                        pageSize: pageSize
                    )
                }
                .onEnded { value in
                    guard model.tool == .select else { return }
                    let transform = DocumentAnnotationInteraction.moved(
                        from: annotation.transform,
                        translation: value.translation,
                        pageSize: pageSize
                    )
                    guard transform != annotation.transform else {
                        model.selectAnnotation(annotation.id)
                        return
                    }
                    model.selectAnnotation(annotation.id)
                    model.transformSelected(centerX: transform.centerX, centerY: transform.centerY)
                }
        }

        private func resizeGesture(_ corner: ImageResizeCorner) -> some Gesture {
            DragGesture(minimumDistance: 8, coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .updating($resizePreview) { value, preview, _ in
                    preview = DocumentImageInteraction.resized(
                        from: annotation.transform,
                        corner: corner,
                        translation: value.translation,
                        pageSize: pageSize,
                        minimumDimension: 0
                    )
                }
                .onEnded { value in
                    let transform = DocumentImageInteraction.resized(
                        from: annotation.transform,
                        corner: corner,
                        translation: value.translation,
                        pageSize: pageSize,
                        minimumDimension: 0
                    )
                    guard transform != annotation.transform else { return }
                    model.selectAnnotation(annotation.id)
                    model.transformSelected(
                        centerX: transform.centerX,
                        centerY: transform.centerY,
                        width: transform.width,
                        height: transform.height
                    )
                }
        }

        private func moveAccessible(horizontal: Double, vertical: Double) {
            model.selectAnnotation(annotation.id)
            model.transformSelected(
                centerX: min(max(annotation.transform.centerX + horizontal, 0), 1),
                centerY: min(max(annotation.transform.centerY + vertical, 0), 1)
            )
        }

        private func resizeAccessible(by scale: Double) {
            model.selectAnnotation(annotation.id)
            model.transformSelected(scale: scale)
        }
    }

    struct SignaturePlacementOverlay: View {
        @Bindable var model: DocumentEditorModel
        let pageSize: CGSize
        @GestureState private var preview: AnnotationTransform?

        var body: some View {
            if let pending = model.pendingSignaturePlacement {
                ZStack {
                    if let transform = preview {
                        SignatureStrokeCanvas(strokes: pending.strokes)
                            .frame(
                                width: transform.width * pageSize.width,
                                height: transform.height * pageSize.height
                            )
                            .overlay {
                                Rectangle().stroke(
                                    WatakeColor.brand.primary,
                                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                                )
                            }
                            .position(
                                x: transform.centerX * pageSize.width,
                                y: transform.centerY * pageSize.height
                            )
                            .opacity(0.82)
                            .allowsHitTesting(false)
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(placementGesture(pending))
                }
                .accessibilityLabel("Place signature")
                .accessibilityHint("Tap the page for a default size, or drag to choose the signature size.")
            }
        }

        private func placementGesture(_ pending: PendingSignaturePlacement) -> some Gesture {
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace)
            )
            .updating($preview) { value, preview, _ in
                preview = DocumentImageInteraction.placement(
                    from: value.startLocation,
                    to: value.location,
                    imageAspectRatio: pending.aspectRatio,
                    pageSize: pageSize
                )
            }
            .onEnded { value in
                let transform = DocumentImageInteraction.placement(
                    from: value.startLocation,
                    to: value.location,
                    imageAspectRatio: pending.aspectRatio,
                    pageSize: pageSize
                )
                _ = model.placePendingSignature(transform: transform)
            }
        }
    }

    private struct SignatureContextToolbar<Move: Gesture>: View {
        let rotation: Double
        let usesCompactControls: Bool
        let moveGesture: Move
        let delete: () -> Void
        let duplicate: () -> Void
        let showColor: () -> Void
        let showResize: () -> Void

        var body: some View {
            HStack(spacing: WatakeSpacing.xxs) {
                if usesCompactControls {
                    gestureControl(icon: "arrow.up.and.down.and.arrow.left.and.right", label: "Move signature")
                        .gesture(moveGesture)
                }
                actionButton(icon: "arrow.up.left.and.arrow.down.right", label: "Resize signature", action: showResize)
                actionButton(icon: "trash", label: "Delete signature", role: .destructive, action: delete)
                actionButton(icon: "doc.on.doc", label: "Copy signature", action: duplicate)
                actionButton(icon: "paintpalette", label: "Signature color", action: showColor)
            }
            .padding(WatakeSpacing.xxs)
            .background(WatakeColor.surface.raised)
            .clipShape(Capsule())
            .shadow(color: WatakeColor.text.primary.opacity(0.18), radius: 8, y: 3)
            .rotationEffect(.degrees(-rotation))
        }

        private func gestureControl(icon: String, label: String) -> some View {
            Image(systemName: icon)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .foregroundStyle(WatakeColor.text.primary)
                .accessibilityLabel(label)
        }

        private func actionButton(
            icon: String,
            label: String,
            role: ButtonRole? = nil,
            action: @escaping () -> Void
        ) -> some View {
            Button(role: role, action: action) {
                Image(systemName: icon)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(role == .destructive ? WatakeColor.status.danger : WatakeColor.text.primary)
            .accessibilityLabel(label)
        }
    }
#endif
