//
//  ExportSettingsInspector.swift
//  ExportFeature
//

import DesignSystem
import SwiftUI
import WatakeDomain

public struct ExportSettingsInspector: View {
    @Bindable private var model: ExportFeatureModel
    @State private var isDocumentSettingsExpanded = true
    @State private var isLayoutSettingsExpanded = true

    public init(model: ExportFeatureModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: WatakeSpacing.lg) {
            WatakeInspectorSection(
                String(localized: "Document", comment: "Section title for document settings"),
                isExpanded: $isDocumentSettingsExpanded
            ) {
                VStack(spacing: WatakeSpacing.md) {
                    VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                        Text(String(localized: "Filename", comment: "Label for filename input"))
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)

                        TextField(
                            String(localized: "Filename", comment: "Placeholder for filename"),
                            text: Binding(
                                get: { model.draft?.outputFilename ?? "" },
                                set: { model.setFilename($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text(String(localized: "Pages to Export", comment: "Label for included pages count"))
                            .watakeType(.body)
                            .foregroundStyle(WatakeColor.text.primary)
                        Spacer()
                        Text("\(model.draft?.includedItems.count ?? 0)")
                            .watakeType(.bodyEmphasis)
                            .foregroundStyle(WatakeColor.text.secondary)
                    }
                }
            }

            Divider()

            WatakeInspectorSection(
                String(localized: "Layout", comment: "Section title for layout settings"),
                isExpanded: $isLayoutSettingsExpanded
            ) {
                VStack(spacing: WatakeSpacing.md) {
                    VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                        Text(String(localized: "Page Size", comment: "Label for page size picker"))
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)

                        Picker(String(localized: "Page Size", comment: "Accessibility label for page size picker"), selection: Binding(
                            get: { model.draft?.pageSize ?? .a4 },
                            set: { model.setPageSize($0) }
                        )) {
                            Text(String(localized: "Original", comment: "Page size option")).tag(ExportPageSize.original)
                            Text(String(localized: "A4", comment: "Page size option")).tag(ExportPageSize.a4)
                            Text(String(localized: "US Letter", comment: "Page size option")).tag(ExportPageSize.usLetter)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                        Text(String(localized: "Fit Mode", comment: "Label for fit mode segmented control"))
                            .watakeType(.caption)
                            .foregroundStyle(WatakeColor.text.secondary)

                        Picker(String(localized: "Fit Mode", comment: "Accessibility label for fit mode"), selection: Binding(
                            get: { model.draft?.fitMode ?? .fit },
                            set: { model.setFitMode($0) }
                        )) {
                            Text(String(localized: "Fit", comment: "Fit mode option")).tag(ExportFitMode.fit)
                            Text(String(localized: "Fill", comment: "Fill mode option")).tag(ExportFitMode.fill)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: WatakeSpacing.xxs) {
                        Stepper(value: Binding(
                            get: { model.draft?.marginPoints ?? 0 },
                            set: { model.setMargin($0) }
                        ), in: 0 ... 72, step: 4) {
                            HStack {
                                Text(String(localized: "Margin", comment: "Label for margin stepper"))
                                    .watakeType(.caption)
                                    .foregroundStyle(WatakeColor.text.secondary)
                                Spacer()
                                Text("\(Int(model.draft?.marginPoints ?? 0)) pt")
                                    .watakeType(.body)
                                    .foregroundStyle(WatakeColor.text.primary)
                            }
                        }
                    }
                }
            }
        }
    }
}
