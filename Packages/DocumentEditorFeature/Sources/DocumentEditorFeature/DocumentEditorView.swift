#if canImport(UIKit)
    import DesignSystem
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers
    import WatakeDomain

    public struct DocumentEditorView: View {
        @Bindable private var model: DocumentEditorModel
        private let onClose: () -> Void
        private let onExportRequested: ((StoredDocument) -> Void)?
        @State private var asksToDiscard = false
        @State private var asksToRevert = false
        @State private var showsSaveCopy = false
        @State private var showsSignature = false
        @State private var showsPageTargets = false
        @State private var showsFileImporter = false
        @State private var photoItem: PhotosPickerItem?

        public init(
            model: DocumentEditorModel,
            onExportRequested: ((StoredDocument) -> Void)? = nil,
            onClose: @escaping () -> Void
        ) {
            self.model = model
            self.onExportRequested = onExportRequested
            self.onClose = onClose
        }

        public var body: some View {
            NavigationStack {
                GeometryReader { proxy in
                    let widthClass = WatakeLayout.widthClass(for: proxy.size.width)
                    editor(widthClass: widthClass)
                }
                .background(WatakeColor.surface.base)
                .navigationTitle("Edit Document")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
            }
            .task { await model.load() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    _ = await model.importImage(data: data, mediaType: "image/jpeg", fileExtension: "jpg")
                    photoItem = nil
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.png, .jpeg, .heic],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let data = try? Data(contentsOf: url) else { return }
                let type = UTType(filenameExtension: url.pathExtension)
                Task {
                    _ = await model.importImage(
                        data: data,
                        mediaType: type?.preferredMIMEType ?? "application/octet-stream",
                        fileExtension: url.pathExtension
                    )
                }
            }
            .sheet(isPresented: $showsSaveCopy) { SaveCopySheet(model: model) }
            .sheet(isPresented: $showsSignature) { SignatureSheet(model: model) }
            .sheet(isPresented: $showsPageTargets) { PageTargetsSheet(model: model) }
            .alert("Discard changes?", isPresented: $asksToDiscard) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    Task {
                        await model.discardCurrentDraft()
                        onClose()
                    }
                }
            } message: {
                Text("Unsaved page edits will be removed. Source scans stay unchanged.")
            }
            .alert("Revert all edits?", isPresented: $asksToRevert) {
                Button("Cancel", role: .cancel) {}
                Button("Revert", role: .destructive) { model.revertAllEdits() }
            } message: {
                Text("All editable layers will be removed. Source pages, OCR, and existing watermarked copies stay unchanged.")
            }
            .alert("Continue previous draft?", isPresented: recoveryBinding) {
                Button("Discard Draft", role: .destructive) { Task { await model.discardRecoveryDraft() } }
                Button("Continue Editing") { Task { await model.resumeRecoveryDraft() } }
            } message: {
                Text("Watake recovered unsaved edits from this device.")
            }
            .alert("Editor", isPresented: messageBinding) {
                Button("OK") { model.clearMessage() }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if model.saveState == .savedCopy {
                    Label("Copy saved", systemImage: "checkmark.circle.fill")
                        .watakeType(.bodyEmphasis)
                        .padding(.horizontal, WatakeSpacing.md)
                        .padding(.vertical, WatakeSpacing.sm)
                        .background(WatakeColor.surface.raised)
                        .clipShape(Capsule())
                        .padding(WatakeSpacing.md)
                }
            }
        }

        @ToolbarContentBuilder
        private var editorToolbar: some ToolbarContent {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if model.isDirty {
                        asksToDiscard = true
                    } else {
                        onClose()
                    }
                }
            }
            ToolbarItem(placement: .principal) { pageCounter }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                    .accessibilityLabel("Undo page edit")
                    .keyboardShortcut("z", modifiers: .command)
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                    .accessibilityLabel("Redo page edit")
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Menu {
                    Button { showsSaveCopy = true } label: { Label("Save a Copy…", systemImage: "doc.on.doc") }
                    if let onExportRequested {
                        Button {
                            onClose()
                            onExportRequested(model.document)
                        } label: { Label("Export PDF", systemImage: "square.and.arrow.up") }
                    }
                    Button { showsFileImporter = true } label: { Label("Import Image from Files", systemImage: "folder") }
                    Divider()
                    Button(role: .destructive) { asksToRevert = true } label: {
                        Label("Revert All Edits", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!model.pages.contains(where: { !$0.annotations.isEmpty }))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Editor actions")
                Button("Done") {
                    Task {
                        if await model.save() {
                            onClose()
                        }
                    }
                }
                .disabled(model.saveState == .saving)
                .fontWeight(.semibold)
            }
        }

        @ViewBuilder
        private func editor(widthClass: WatakeWidthClass) -> some View {
            if widthClass == .compact {
                VStack(spacing: 0) {
                    DocumentCanvas(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    PageRail(model: model, axis: .horizontal)
                        .frame(height: 92)
                    ToolDock(model: model, photoItem: $photoItem, showSignature: { showsSignature = true })
                    if model.selectedAnnotation != nil {
                        AnnotationInspector(model: model, showPageTargets: { showsPageTargets = true })
                    }
                }
            } else {
                HStack(spacing: 0) {
                    PageRail(model: model, axis: .vertical)
                        .frame(width: 112)
                        .background(WatakeColor.surface.raised)
                    Divider()
                    VStack(spacing: 0) {
                        DocumentCanvas(model: model)
                            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                        ToolDock(model: model, photoItem: $photoItem, showSignature: { showsSignature = true })
                    }
                    Divider()
                    ScrollView {
                        AnnotationInspector(model: model, showPageTargets: { showsPageTargets = true })
                            .padding(WatakeSpacing.md)
                    }
                    .frame(width: min(max(320, 340), 380))
                    .background(WatakeColor.surface.raised)
                }
            }
        }

        private var pageCounter: some View {
            Text("Page \((model.selectedPage?.index ?? 0) + 1) of \(model.pages.count)")
                .watakeType(.caption)
                .foregroundStyle(WatakeColor.text.secondary)
                .padding(.vertical, WatakeSpacing.xs)
        }

        private var recoveryBinding: Binding<Bool> {
            Binding(get: { model.recoveryDraftAvailable }, set: { _ in })
        }

        private var messageBinding: Binding<Bool> {
            Binding(get: { model.errorMessage != nil }, set: {
                if !$0 {
                    model.clearMessage()
                }
            })
        }
    }

    private struct ToolDock: View {
        @Bindable var model: DocumentEditorModel
        @Binding var photoItem: PhotosPickerItem?
        let showSignature: () -> Void

        var body: some View {
            HStack(spacing: WatakeSpacing.xs) {
                toolButton(.select, icon: "arrow.up.left.and.arrow.down.right") { model.tool = .select }
                toolButton(.text, icon: "textformat") { model.addText() }
                toolButton(.signature, icon: "signature") { showSignature() }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    VStack(spacing: WatakeSpacing.xxs) {
                        Image(systemName: "photo").font(.body)
                        Text("Image").watakeType(.overline)
                    }
                    .foregroundStyle(WatakeColor.text.secondary)
                    .frame(minWidth: 52, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Image")
                }
                .buttonStyle(.plain)
                toolButton(.highlight, icon: "highlighter") { model.tool = .highlight }
            }
            .padding(.horizontal, WatakeSpacing.sm)
            .padding(.vertical, WatakeSpacing.xs)
            .frame(maxWidth: .infinity)
            .background(WatakeColor.surface.raised)
            .overlay(alignment: .top) { Divider() }
        }

        private func toolButton(_ tool: DocumentEditorTool, icon: String, action: @escaping () -> Void) -> some View {
            Button(action: action) { toolLabel(tool, icon: icon) }.buttonStyle(.plain)
        }

        private func toolLabel(_ tool: DocumentEditorTool, icon: String) -> some View {
            VStack(spacing: WatakeSpacing.xxs) {
                Image(systemName: icon).font(.body)
                Text(tool.rawValue.capitalized).watakeType(.overline)
            }
            .foregroundStyle(model.tool == tool ? WatakeColor.brand.primary : WatakeColor.text.secondary)
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tool.rawValue.capitalized)
        }
    }

    private struct PageRail: View {
        @Bindable var model: DocumentEditorModel
        let axis: Axis

        var body: some View {
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                if axis == .horizontal {
                    HStack(spacing: WatakeSpacing.xs) { pages }
                        .padding(WatakeSpacing.xs)
                } else {
                    LazyVStack(spacing: WatakeSpacing.xs) { pages }
                        .padding(WatakeSpacing.xs)
                }
            }
            .task {
                for page in model.pages where model.pageImages[page.id] == nil {
                    await model.loadPageImage(for: page.id)
                }
            }
        }

        private var pages: some View {
            ForEach(model.pages) { page in
                Button { model.selectPage(page.id) } label: {
                    VStack(spacing: WatakeSpacing.xxs) {
                        if let data = model.pageImages[page.id], let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            Rectangle().fill(WatakeColor.surface.sunken).overlay { ProgressView() }
                        }
                        Text("\(page.index + 1)").watakeType(.caption)
                    }
                    .frame(width: 70, height: 78)
                    .padding(WatakeSpacing.xxs)
                    .background(WatakeColor.surface.base)
                    .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: WatakeRadius.sm)
                            .stroke(page.id == model.selectedPageID ? WatakeColor.brand.primary : WatakeColor.border.subtle, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(page.index + 1)")
            }
        }
    }

    private struct DocumentCanvas: View {
        @Bindable var model: DocumentEditorModel
        @State private var zoomScale = 1.0
        @State private var lastMagnification = 1.0

        var body: some View {
            GeometryReader { proxy in
                if let page = model.selectedPage,
                   let data = model.pageImages[page.id],
                   let image = UIImage(data: data) {
                    let rect = fittedRect(imageSize: image.size, container: proxy.size)
                    ScrollView([.horizontal, .vertical]) {
                        PageSurface(model: model, image: image)
                            .frame(width: rect.width * zoomScale, height: rect.height * zoomScale)
                            .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                    }
                    .background(WatakeColor.surface.sunken)
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(zoomGesture)
                    .overlay(alignment: .bottomTrailing) { zoomControls }
                } else {
                    ProgressView("Loading page")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }

        private var zoomGesture: some Gesture {
            MagnifyGesture()
                .onChanged { value in
                    guard model.selectedAnnotationID == nil else { return }
                    let increment = value.magnification / lastMagnification
                    zoomScale = min(max(zoomScale * increment, 1), 4)
                    lastMagnification = value.magnification
                }
                .onEnded { _ in lastMagnification = 1 }
        }

        private var zoomControls: some View {
            HStack(spacing: WatakeSpacing.xxs) {
                Button { zoomScale = max(1, zoomScale - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(zoomScale <= 1)
                    .accessibilityLabel("Zoom out")
                Button { zoomScale = 1 } label: { Text("Fit").watakeType(.caption) }
                    .accessibilityLabel("Fit page")
                Button { zoomScale = min(4, zoomScale + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(zoomScale >= 4)
                    .accessibilityLabel("Zoom in")
            }
            .buttonStyle(.bordered)
            .padding(WatakeSpacing.sm)
        }

        private func fittedRect(imageSize: CGSize, container: CGSize) -> CGRect {
            let inset = WatakeSpacing.md
            let available = CGSize(width: max(1, container.width - inset * 2), height: max(1, container.height - inset * 2))
            let scale = min(available.width / imageSize.width, available.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            return CGRect(
                x: (container.width - size.width) / 2,
                y: (container.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    private struct PageSurface: View {
        @Bindable var model: DocumentEditorModel
        let image: UIImage
        @State private var highlightPoints: [InkPoint] = []
        @State private var highlightStartedAt: Date?
        @State private var highlightLastMovedAt: Date?

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    Color.white
                        .onTapGesture {
                            if model.tool == .select {
                                model.selectAnnotation(nil)
                            }
                        }
                    Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
                    ForEach(model.selectedPage?.annotations.sorted(by: { $0.zIndex < $1.zIndex }) ?? []) { annotation in
                        AnnotationLayer(model: model, annotation: annotation, pageSize: proxy.size)
                    }
                    alignmentGuides(size: proxy.size)
                    if model.tool == .highlight {
                        HighlightCapture(points: $highlightPoints)
                            .contentShape(Rectangle())
                            .gesture(highlightGesture(size: proxy.size))
                    }
                }
                .clipped()
                .background(Color.white)
                .overlay(Rectangle().stroke(WatakeColor.border.strong, lineWidth: 1))
                .accessibilityLabel("Editable document page")
            }
        }

        @ViewBuilder
        private func alignmentGuides(size: CGSize) -> some View {
            if let transform = model.selectedAnnotation?.transform {
                if transform.centerX == 0.5 {
                    Rectangle()
                        .fill(WatakeColor.brand.primary.opacity(0.65))
                        .frame(width: 1, height: size.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if transform.centerY == 0.5 {
                    Rectangle()
                        .fill(WatakeColor.brand.primary.opacity(0.65))
                        .frame(width: size.width, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }

        private func highlightGesture(size: CGSize) -> some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let timestamp = Date()
                    if highlightStartedAt == nil {
                        highlightStartedAt = timestamp
                        highlightLastMovedAt = timestamp
                    }
                    let next = InkPoint(location: .init(
                        x: min(max(value.location.x / size.width, 0), 1),
                        y: min(max(value.location.y / size.height, 0), 1)
                    ))
                    if let previous = highlightPoints.last {
                        let distance = hypot(next.location.x - previous.location.x, next.location.y - previous.location.y)
                        if distance > 0.005 {
                            highlightLastMovedAt = timestamp
                        }
                    }
                    highlightPoints.append(next)
                }
                .onEnded { _ in
                    let straightened = Date().timeIntervalSince(highlightLastMovedAt ?? Date()) >= 0.35
                    model.addHighlight(points: highlightPoints, straightened: straightened)
                    highlightPoints = []
                    highlightStartedAt = nil
                    highlightLastMovedAt = nil
                }
        }
    }

    private struct HighlightCapture: View {
        @Binding var points: [InkPoint]
        var body: some View {
            Canvas { context, size in
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: CGPoint(x: first.location.x * size.width, y: first.location.y * size.height))
                for point in points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.location.x * size.width, y: point.location.y * size.height))
                }
                context.stroke(
                    path,
                    with: .color(WatakeColor.status.warning.opacity(0.42)),
                    style: .init(lineWidth: 14, lineCap: .round, lineJoin: .round)
                )
            }
            .allowsHitTesting(true)
        }
    }

    private struct AnnotationLayer: View {
        @Bindable var model: DocumentEditorModel
        let annotation: PageAnnotation
        let pageSize: CGSize
        @State private var dragStart: AnnotationTransform?
        @State private var lastScale = 1.0
        @State private var lastRotation = Angle.zero

        var body: some View {
            content
                .frame(width: annotation.transform.width * pageSize.width, height: annotation.transform.height * pageSize.height)
                .overlay {
                    if model.selectedAnnotationID == annotation.id {
                        Rectangle().stroke(WatakeColor.brand.primary, style: .init(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .rotationEffect(.degrees(annotation.transform.rotation))
                .opacity(annotation.opacity)
                .position(x: annotation.transform.centerX * pageSize.width, y: annotation.transform.centerY * pageSize.height)
                .contentShape(Rectangle())
                .onTapGesture { model.selectAnnotation(annotation.id) }
                .gesture(transformGesture)
                .accessibilityLabel("\(annotation.kind.rawValue.capitalized) annotation")
                .accessibilityHint("Double tap to select, then use inspector actions")
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
                        .foregroundStyle(contentColor(text.colorHex))
                        .multilineTextAlignment(swiftAlignment(text.alignment))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(text.alignment))
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

        private var transformGesture: some Gesture {
            let drag = DragGesture().onChanged { value in
                guard model.tool == .select else { return }
                if dragStart == nil {
                    model.selectAnnotation(annotation.id)
                    dragStart = annotation.transform
                    model.beginContinuousEdit()
                }
                guard let start = dragStart else { return }
                model.transformSelected(
                    centerX: start.centerX + value.translation.width / pageSize.width,
                    centerY: start.centerY + value.translation.height / pageSize.height
                )
            }.onEnded { _ in
                dragStart = nil
                model.endContinuousEdit()
            }
            let scale = MagnifyGesture().onChanged { value in
                guard model.tool == .select else { return }
                if lastScale == 1 {
                    model.selectAnnotation(annotation.id)
                    model.beginContinuousEdit()
                }
                model.transformSelected(scale: value.magnification / lastScale)
                lastScale = value.magnification
            }.onEnded { _ in
                lastScale = 1
                model.endContinuousEdit()
            }
            let rotate = RotateGesture().onChanged { value in
                guard model.tool == .select else { return }
                if lastRotation == .zero {
                    model.selectAnnotation(annotation.id)
                    model.beginContinuousEdit()
                }
                model.transformSelected(rotationDelta: value.rotation.degrees - lastRotation.degrees)
                lastRotation = value.rotation
            }.onEnded { _ in
                lastRotation = .zero
                model.endContinuousEdit()
            }
            return drag.simultaneously(with: scale).simultaneously(with: rotate)
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
                        with: .color(contentColor(stroke.colorHex).opacity(stroke.opacity)),
                        style: .init(lineWidth: max(1, stroke.width * min(size.width, size.height)), lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }

    private struct AnnotationInspector: View {
        @Bindable var model: DocumentEditorModel
        let showPageTargets: () -> Void

        var body: some View {
            if let annotation = model.selectedAnnotation {
                VStack(alignment: .leading, spacing: WatakeSpacing.sm) {
                    Text(annotation.kind.rawValue.capitalized).watakeType(.title2)
                    if let text = annotation.text {
                        textControls(text)
                    }
                    if annotation.kind == .signature || annotation.kind == .highlight {
                        strokeControls(annotation)
                    }
                    VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                        Text("Opacity").watakeType(.caption)
                        Slider(value: Binding(
                            get: { model.selectedAnnotation?.opacity ?? 1 },
                            set: { model.updateSelectedOpacity($0) }
                        ), in: 0 ... 1)
                    }
                    HStack {
                        Button { model.sendBackward() } label: { Label("Back", systemImage: "square.2.layers.3d.bottom.filled") }
                        Button { model.bringForward() } label: { Label("Front", systemImage: "square.2.layers.3d.top.filled") }
                    }
                    .buttonStyle(.bordered)
                    Menu("Duplicate") {
                        Button("This Page") { model.duplicateSelected() }
                        Button("Selected Pages…", action: showPageTargets)
                        Button("All Pages") { model.duplicateSelected(to: Set(model.pages.map(\.id))) }
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) { model.deleteSelected() } label: { Label("Delete Layer", systemImage: "trash") }
                        .buttonStyle(.bordered)
                }
                .padding(WatakeSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WatakeColor.surface.raised)
            } else {
                VStack(spacing: WatakeSpacing.sm) {
                    Image(systemName: "hand.tap").font(.title2)
                    Text("Select a layer to edit its style and position.")
                        .watakeType(.body)
                        .foregroundStyle(WatakeColor.text.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(WatakeSpacing.md)
            }
        }

        private func textControls(_ text: AnnotationText) -> some View {
            VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                TextEditor(text: Binding(
                    get: { model.selectedAnnotation?.text?.text ?? "" },
                    set: { updateText(text, value: $0) }
                ))
                .frame(minHeight: 80)
                .padding(WatakeSpacing.xxs)
                .background(WatakeColor.surface.base)
                .clipShape(RoundedRectangle(cornerRadius: WatakeRadius.sm))
                HStack {
                    Toggle("Bold", isOn: Binding(get: { text.isBold }, set: { updateStyle(text, bold: $0) }))
                    Toggle("Italic", isOn: Binding(get: { text.isItalic }, set: { updateStyle(text, italic: $0) }))
                    Toggle("Underline", isOn: Binding(get: { text.isUnderlined }, set: { updateStyle(text, underlined: $0) }))
                }
                Picker("Font", selection: Binding(
                    get: { model.selectedAnnotation?.text?.fontName ?? "Helvetica" },
                    set: { updateStyle(text, fontName: $0) }
                )) {
                    ForEach(["Helvetica", "Georgia", "Courier"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Alignment", selection: Binding(
                    get: { model.selectedAnnotation?.text?.alignment ?? .leading },
                    set: { updateStyle(text, alignment: $0) }
                )) {
                    ForEach(AnnotationTextAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Text size").watakeType(.caption)
                Slider(value: Binding(
                    get: { model.selectedAnnotation?.text?.fontSize ?? 0.04 },
                    set: { updateStyle(text, size: $0) }
                ), in: 0.01 ... 0.15)
                colorButtons(current: text.colorHex) { updateStyle(text, color: $0) }
            }
        }

        private func strokeControls(_ annotation: PageAnnotation) -> some View {
            let stroke = annotation.strokes.first
            return VStack(alignment: .leading, spacing: WatakeSpacing.xs) {
                Text("Stroke width").watakeType(.caption)
                Slider(value: Binding(
                    get: { model.selectedAnnotation?.strokes.first?.width ?? 0.02 },
                    set: {
                        model.updateSelectedStrokeStyle(width: $0, colorHex: stroke?.colorHex ?? "#0B1220", opacity: stroke?.opacity ?? 1)
                    }
                ), in: 0.002 ... 0.08)
                colorButtons(current: stroke?.colorHex ?? "#0B1220") {
                    model.updateSelectedStrokeStyle(width: stroke?.width ?? 0.02, colorHex: $0, opacity: stroke?.opacity ?? 1)
                }
            }
        }

        private func colorButtons(current: String, update: @escaping (String) -> Void) -> some View {
            HStack {
                ForEach(["#0B1220", "#1F4FEB", "#B91C1C", "#FBBF24"], id: \.self) { hex in
                    Button { update(hex) } label: {
                        Circle().fill(contentColor(hex)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(current == hex ? WatakeColor.brand.primary : WatakeColor.border.strong, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose color \(hex)")
                }
            }
        }

        private func updateText(_ current: AnnotationText, value: String) {
            model.updateSelectedText(AnnotationText(
                text: value.isEmpty ? "Text" : value, fontName: current.fontName, fontSize: current.fontSize,
                colorHex: current.colorHex, alignment: current.alignment, isBold: current.isBold,
                isItalic: current.isItalic, isUnderlined: current.isUnderlined
            ))
        }

        private func updateStyle(
            _ current: AnnotationText,
            bold: Bool? = nil,
            italic: Bool? = nil,
            underlined: Bool? = nil,
            fontName: String? = nil,
            size: Double? = nil,
            color: String? = nil,
            alignment: AnnotationTextAlignment? = nil
        ) {
            model.updateSelectedText(AnnotationText(
                text: current.text, fontName: fontName ?? current.fontName, fontSize: size ?? current.fontSize,
                colorHex: color ?? current.colorHex, alignment: alignment ?? current.alignment,
                isBold: bold ?? current.isBold, isItalic: italic ?? current.isItalic,
                isUnderlined: underlined ?? current.isUnderlined
            ))
        }
    }

    private func contentColor(_ hex: String) -> Color {
        guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return WatakeColor.text.primary }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private func swiftAlignment(_ alignment: AnnotationTextAlignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func frameAlignment(_ alignment: AnnotationTextAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
#endif
