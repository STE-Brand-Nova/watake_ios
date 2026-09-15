#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import WatakeDomain

    struct ImageAnnotationLayer: View {
        @Bindable var model: DocumentEditorModel
        let annotation: PageAnnotation
        let pageSize: CGSize
        let showImageStyle: (UUID) -> Void
        @GestureState private var movePreview: AnnotationTransform?
        @GestureState private var resizePreview: AnnotationTransform?
        @GestureState private var rotationPreview: AnnotationTransform?

        var body: some View {
            ZStack {
                imageContent
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
            .accessibilityLabel("Image annotation")
            .accessibilityHint("Tap to select or drag to reposition.")
            .accessibilityAction(named: "Move left") { moveAccessible(x: -0.02, y: 0) }
            .accessibilityAction(named: "Move right") { moveAccessible(x: 0.02, y: 0) }
            .accessibilityAction(named: "Move up") { moveAccessible(x: 0, y: -0.02) }
            .accessibilityAction(named: "Move down") { moveAccessible(x: 0, y: 0.02) }
            .accessibilityAction(named: "Increase size") { resizeAccessible(by: 1.1) }
            .accessibilityAction(named: "Decrease size") { resizeAccessible(by: 0.9) }
        }

        private var isSelected: Bool {
            model.selectedAnnotationID == annotation.id
        }

        private var displayedTransform: AnnotationTransform {
            rotationPreview ?? resizePreview ?? movePreview ?? annotation.transform
        }

        @ViewBuilder private var imageContent: some View {
            if let reference = annotation.image, let data = model.annotationImages[reference.id] {
                EditableAnnotationImage(id: reference.id, data: data, targetSize: pageSize)
                    .scaleEffect(
                        x: annotation.isFlippedHorizontally ? -1 : 1,
                        y: annotation.isFlippedVertically ? -1 : 1
                    )
            }
        }

        private var selectionControls: some View {
            GeometryReader { proxy in
                Rectangle()
                    .fill(WatakeColor.brand.primary)
                    .frame(width: 2, height: 30)
                    .position(x: proxy.size.width / 2, y: rotationControlAppearsInside ? 15 : -15)
                    .allowsHitTesting(false)

                selectionHandle(.topLeading, horizontalPosition: 22, verticalPosition: 22)
                selectionHandle(.topTrailing, horizontalPosition: proxy.size.width - 22, verticalPosition: 22)
                selectionHandle(.bottomLeading, horizontalPosition: 22, verticalPosition: proxy.size.height - 22)
                selectionHandle(
                    .bottomTrailing,
                    horizontalPosition: proxy.size.width - 22,
                    verticalPosition: proxy.size.height - 22
                )

                ImageRotationHandle(rotation: displayedTransform.rotation)
                    .position(x: proxy.size.width / 2, y: rotationControlAppearsInside ? 38 : -38)
                    .gesture(rotationGesture)
                    .accessibilityAction(named: "Rotate clockwise") { rotate(by: 15) }
                    .accessibilityAction(named: "Rotate counterclockwise") { rotate(by: -15) }

                if rotationPreview != nil {
                    Text("\(displayedAngle)°")
                        .watakeType(.caption)
                        .foregroundStyle(WatakeColor.text.primary)
                        .padding(.horizontal, WatakeSpacing.xs)
                        .padding(.vertical, WatakeSpacing.xxs)
                        .background(WatakeColor.surface.raised)
                        .clipShape(Capsule())
                        .rotationEffect(.degrees(-displayedTransform.rotation))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .allowsHitTesting(false)
                }

                ImageContextToolbar(
                    rotation: displayedTransform.rotation,
                    delete: {
                        model.selectAnnotation(annotation.id)
                        model.deleteSelected()
                    },
                    duplicate: {
                        model.selectAnnotation(annotation.id)
                        model.duplicateSelected()
                    },
                    showMore: { showImageStyle(annotation.id) }
                )
                .position(
                    x: proxy.size.width / 2,
                    y: toolbarVerticalPosition(in: proxy.size)
                )
            }
        }

        private func selectionHandle(
            _ corner: ImageResizeCorner,
            horizontalPosition: CGFloat,
            verticalPosition: CGFloat
        ) -> some View {
            ImageSelectionHandle(
                label: "Resize image from \(corner.accessibilityName) corner",
                corner: corner,
                resize: resizeAccessible
            )
            .position(x: horizontalPosition, y: verticalPosition)
            .gesture(resizeGesture(corner))
        }

        private var rotationControlAppearsInside: Bool {
            topEdge < 54
        }

        private var topEdge: CGFloat {
            let radians = displayedTransform.rotation * .pi / 180
            let width = displayedTransform.width * pageSize.width
            let height = displayedTransform.height * pageSize.height
            let projectedHalfHeight = abs(sin(radians)) * width / 2 + abs(cos(radians)) * height / 2
            return displayedTransform.centerY * pageSize.height - projectedHalfHeight
        }

        private var bottomEdge: CGFloat {
            let radians = displayedTransform.rotation * .pi / 180
            let width = displayedTransform.width * pageSize.width
            let height = displayedTransform.height * pageSize.height
            let projectedHalfHeight = abs(sin(radians)) * width / 2 + abs(cos(radians)) * height / 2
            return displayedTransform.centerY * pageSize.height + projectedHalfHeight
        }

        private func toolbarVerticalPosition(in size: CGSize) -> CGFloat {
            if bottomEdge <= pageSize.height - 64 {
                return size.height + 34
            }
            if topEdge >= 104 {
                return -92
            }
            return max(34, size.height - 34)
        }

        private var displayedAngle: Int {
            let rounded = Int(displayedTransform.rotation.rounded())
            return (rounded % 360 + 360) % 360
        }

        private var moveGesture: some Gesture {
            DragGesture(coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
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
                    guard transform != annotation.transform else { return }
                    model.selectAnnotation(annotation.id)
                    model.transformSelected(centerX: transform.centerX, centerY: transform.centerY)
                }
        }

        private func resizeGesture(_ corner: ImageResizeCorner) -> some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .updating($resizePreview) { value, preview, _ in
                    preview = DocumentImageInteraction.resized(
                        from: annotation.transform,
                        corner: corner,
                        location: value.location,
                        pageSize: pageSize
                    )
                }
                .onEnded { value in
                    let transform = DocumentImageInteraction.resized(
                        from: annotation.transform,
                        corner: corner,
                        location: value.location,
                        pageSize: pageSize
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

        private var rotationGesture: some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .named(DocumentAnnotationInteraction.pageCoordinateSpace))
                .updating($rotationPreview) { value, preview, _ in
                    preview = DocumentImageInteraction.rotated(
                        from: annotation.transform,
                        startLocation: value.startLocation,
                        location: value.location,
                        pageSize: pageSize
                    )
                }
                .onEnded { value in
                    let transform = DocumentImageInteraction.rotated(
                        from: annotation.transform,
                        startLocation: value.startLocation,
                        location: value.location,
                        pageSize: pageSize
                    )
                    guard transform != annotation.transform else { return }
                    model.selectAnnotation(annotation.id)
                    model.transformSelected(rotationDelta: transform.rotation - annotation.transform.rotation)
                }
        }

        private func rotate(by degrees: Double) {
            model.selectAnnotation(annotation.id)
            model.rotateSelectedImage(by: degrees)
        }

        private func moveAccessible(x horizontalOffset: Double, y verticalOffset: Double) {
            model.selectAnnotation(annotation.id)
            model.transformSelected(
                centerX: min(max(annotation.transform.centerX + horizontalOffset, 0), 1),
                centerY: min(max(annotation.transform.centerY + verticalOffset, 0), 1)
            )
        }

        private func resizeAccessible(by scale: Double) {
            model.selectAnnotation(annotation.id)
            model.transformSelected(scale: scale)
        }
    }

    struct EditableAnnotationImage: View {
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
#endif
