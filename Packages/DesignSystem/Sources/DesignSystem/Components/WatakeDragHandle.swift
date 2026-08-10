//
//  WatakeDragHandle.swift
//  DesignSystem
//

import SwiftUI

/// Drag handle affordance.
///
/// Uses standard system imagery and tokens for reorder controls.
public struct WatakeDragHandle: View {
    public init() {}

    public var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(WatakeColor.text.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(String(localized: "Reorder", comment: "Accessibility label for drag handle to reorder list items"))
    }
}
