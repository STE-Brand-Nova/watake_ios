import Foundation
import WatakeDomain

enum SignatureResizePolicy {
    static func scaleRange(for transform: AnnotationTransform) -> ClosedRange<Double> {
        let minimum = max(0.1, 0.01 / transform.width, 0.01 / transform.height)
        let maximum = min(3, 1 / transform.width, 1 / transform.height)
        return minimum ... maximum
    }

    static func resized(_ transform: AnnotationTransform, scale: Double) -> AnnotationTransform {
        let range = scaleRange(for: transform)
        let clampedScale = min(max(scale, range.lowerBound), range.upperBound)
        return AnnotationTransform(
            centerX: transform.centerX,
            centerY: transform.centerY,
            width: transform.width * clampedScale,
            height: transform.height * clampedScale,
            rotation: transform.rotation
        )
    }
}

#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    struct SignatureResizeSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Bindable var model: DocumentEditorModel
        @State private var baseline: AnnotationTransform?
        @State private var scale = 1.0

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: WatakeSpacing.md) {
                    if let baseline {
                        Text("Adjust signature size")
                            .watakeType(.title2)
                        Text("Changes preview on the page. Proportions stay locked.")
                            .watakeType(.body)
                            .foregroundStyle(WatakeColor.text.secondary)
                        HStack(spacing: WatakeSpacing.sm) {
                            Button {
                                updateScale(scale - 0.05)
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Make signature smaller")

                            Slider(
                                value: Binding(get: { scale }, set: { updateScale($0) }),
                                in: SignatureResizePolicy.scaleRange(for: baseline)
                            )
                            .accessibilityLabel("Signature size")
                            .accessibilityValue("\(Int((scale * 100).rounded())) percent")

                            Button {
                                updateScale(scale + 0.05)
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Make signature larger")
                        }
                        .buttonStyle(.plain)

                        Text("\(Int((scale * 100).rounded()))% of selected size")
                            .watakeType(.bodyEmphasis)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Button("Reset size") { updateScale(1) }
                            .frame(minHeight: 44)
                        Spacer(minLength: 0)
                    }
                }
                .padding(WatakeSpacing.md)
                .navigationTitle("Resize Signature")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium])
            .onAppear {
                guard model.selectedAnnotation?.kind == .signature,
                      let transform = model.selectedAnnotation?.transform else { return }
                baseline = transform
                model.beginContinuousEdit()
            }
            .onDisappear { model.endContinuousEdit() }
        }

        private func updateScale(_ proposed: Double) {
            guard let baseline else { return }
            let range = SignatureResizePolicy.scaleRange(for: baseline)
            scale = min(max(proposed, range.lowerBound), range.upperBound)
            let transform = SignatureResizePolicy.resized(baseline, scale: scale)
            model.transformSelected(width: transform.width, height: transform.height)
        }
    }
#endif
