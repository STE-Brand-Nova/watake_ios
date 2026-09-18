#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    struct DocumentEditorLayout: View {
        @Bindable var model: DocumentEditorModel
        let widthClass: WatakeWidthClass
        let editText: (UUID) -> Void
        let showTextStyle: (UUID) -> Void
        let showHighlightStyle: (UUID) -> Void
        let showImageStyle: (UUID) -> Void
        let showSignatureColor: (UUID) -> Void
        let showSignatureResize: (UUID) -> Void
        let showHighlightDrawingStyle: () -> Void
        let addText: () -> Void
        let showSignature: () -> Void
        let addImage: () -> Void
        let showPageTargets: () -> Void

        var body: some View {
            if widthClass == .compact {
                compactEditor
            } else {
                regularEditor
            }
        }

        private var compactEditor: some View {
            VStack(spacing: 0) {
                DocumentCanvas(
                    model: model,
                    editText: editText,
                    showTextStyle: showTextStyle,
                    showHighlightStyle: showHighlightStyle,
                    showImageStyle: showImageStyle,
                    showSignatureColor: showSignatureColor,
                    showSignatureResize: showSignatureResize
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                PageRail(model: model, axis: .horizontal)
                    .frame(height: 92)
                EditorToolDock(
                    model: model,
                    addText: addText,
                    showSignature: showSignature,
                    addImage: addImage,
                    showHighlightStyle: showHighlightDrawingStyle
                )
            }
        }

        private var regularEditor: some View {
            HStack(spacing: 0) {
                PageRail(model: model, axis: .vertical)
                    .frame(width: 112)
                    .background(WatakeColor.surface.raised)
                Divider()
                VStack(spacing: 0) {
                    DocumentCanvas(
                        model: model,
                        editText: editText,
                        showTextStyle: showTextStyle,
                        showHighlightStyle: showHighlightStyle,
                        showImageStyle: showImageStyle,
                        showSignatureColor: showSignatureColor,
                        showSignatureResize: showSignatureResize
                    )
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    EditorToolDock(
                        model: model,
                        addText: addText,
                        showSignature: showSignature,
                        addImage: addImage,
                        showHighlightStyle: showHighlightDrawingStyle
                    )
                }
                Divider()
                ScrollView {
                    AnnotationInspector(model: model, editText: editText, showPageTargets: showPageTargets)
                        .padding(WatakeSpacing.md)
                }
                .frame(width: min(max(320, 340), 380))
                .background(WatakeColor.surface.raised)
            }
        }
    }

    private struct EditorToolDock: View {
        @Bindable var model: DocumentEditorModel
        let addText: () -> Void
        let showSignature: () -> Void
        let addImage: () -> Void
        let showHighlightStyle: () -> Void
        @AppStorage("watake.editor.didShowHighlightGuide.v2") private var didShowHighlightGuide = false
        @State private var showsHighlightGuide = false

        var body: some View {
            VStack(spacing: 0) {
                if model.tool == .highlight {
                    HighlightDrawControls(
                        model: model,
                        showsGuide: $showsHighlightGuide,
                        shouldPresentGuide: !didShowHighlightGuide,
                        showStyle: showHighlightStyle,
                        dismissGuide: { showsHighlightGuide = false },
                        markGuideShown: { didShowHighlightGuide = true }
                    )
                }
                if model.pendingImagePlacement != nil {
                    HStack(spacing: WatakeSpacing.sm) {
                        Image(systemName: "hand.draw")
                            .foregroundStyle(WatakeColor.brand.primary)
                        Text("Tap to place, or drag to set the image size.")
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)
                        Spacer(minLength: WatakeSpacing.xs)
                        Button("Cancel") { model.cancelImagePlacement() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, WatakeSpacing.md)
                    .padding(.vertical, WatakeSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .background(WatakeColor.surface.raised)
                    .overlay(alignment: .top) { Divider() }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Image placement. Tap the page to place the image, or drag to set its size.")
                }
                if model.pendingSignaturePlacement != nil {
                    HStack(spacing: WatakeSpacing.sm) {
                        Image(systemName: "signature")
                            .foregroundStyle(WatakeColor.brand.primary)
                        Text("Tap to place, or drag to set the signature size.")
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)
                        Spacer(minLength: WatakeSpacing.xs)
                        Button("Cancel") { model.cancelSignaturePlacement() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, WatakeSpacing.md)
                    .padding(.vertical, WatakeSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .background(WatakeColor.surface.raised)
                    .overlay(alignment: .top) { Divider() }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Signature placement. Tap the page to place it, or drag to set its size.")
                }
                HStack(spacing: WatakeSpacing.xs) {
                    toolButton(.select, icon: "hand.point.up.left") { model.activateTool(.select) }
                    toolButton(.text, icon: "textformat", action: addText)
                    toolButton(.signature, icon: "signature") {
                        model.activateTool(.signature)
                        showSignature()
                    }
                    toolButton(.image, icon: "photo", action: addImage)
                    toolButton(.highlight, icon: "highlighter") { model.activateTool(.highlight) }
                }
                .padding(.horizontal, WatakeSpacing.sm)
                .padding(.vertical, WatakeSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(WatakeColor.surface.raised)
                .overlay(alignment: .top) { Divider() }
            }
            .onChange(of: model.tool) { _, tool in
                if tool != .highlight {
                    showsHighlightGuide = false
                }
            }
        }

        private func toolButton(_ tool: DocumentEditorTool, icon: String, action: @escaping () -> Void) -> some View {
            Button(action: action) { toolLabel(tool, icon: icon) }.buttonStyle(.plain)
        }

        private func toolLabel(_ tool: DocumentEditorTool, icon: String) -> some View {
            VStack(spacing: WatakeSpacing.xxs) {
                Image(systemName: icon).font(.body)
                Text(tool == .select ? "View" : tool.rawValue.capitalized).watakeType(.overline)
            }
            .foregroundStyle(model.tool == tool ? WatakeColor.brand.primary : WatakeColor.text.secondary)
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tool == .select ? "View document" : tool.rawValue.capitalized)
        }
    }
#endif
