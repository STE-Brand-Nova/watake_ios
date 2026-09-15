#if canImport(UIKit)
    import DesignSystem
    import PhotosUI
    import SwiftUI

    struct DocumentEditorLayout: View {
        @Bindable var model: DocumentEditorModel
        @Binding var photoItem: PhotosPickerItem?
        let widthClass: WatakeWidthClass
        let editText: (UUID) -> Void
        let showTextStyle: (UUID) -> Void
        let showHighlightStyle: (UUID) -> Void
        let showHighlightDrawingStyle: () -> Void
        let addText: () -> Void
        let showSignature: () -> Void
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
                    showHighlightStyle: showHighlightStyle
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                PageRail(model: model, axis: .horizontal)
                    .frame(height: 92)
                EditorToolDock(
                    model: model,
                    photoItem: $photoItem,
                    addText: addText,
                    showSignature: showSignature,
                    showHighlightStyle: showHighlightDrawingStyle
                )
                if let annotation = model.selectedAnnotation,
                   annotation.kind != .text,
                   annotation.kind != .highlight {
                    AnnotationInspector(model: model, editText: editText, showPageTargets: showPageTargets)
                }
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
                        showHighlightStyle: showHighlightStyle
                    )
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    EditorToolDock(
                        model: model,
                        photoItem: $photoItem,
                        addText: addText,
                        showSignature: showSignature,
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
        @Binding var photoItem: PhotosPickerItem?
        let addText: () -> Void
        let showSignature: () -> Void
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
                HStack(spacing: WatakeSpacing.xs) {
                    toolButton(.select, icon: "hand.point.up.left") { model.activateTool(.select) }
                    toolButton(.text, icon: "textformat", action: addText)
                    toolButton(.signature, icon: "signature") {
                        model.activateTool(.signature)
                        showSignature()
                    }
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
                    .simultaneousGesture(TapGesture().onEnded { model.activateTool(.image) })
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
