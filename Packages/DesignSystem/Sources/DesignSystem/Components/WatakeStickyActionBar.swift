//
//  WatakeStickyActionBar.swift
//  DesignSystem
//

import SwiftUI

/// Sticky bottom action bar for compact layouts.
///
/// Provides a semantic surface for bottom-anchored buttons (like "Create PDF")
/// that site above the safe area, with standard padding and a subtle border.
public struct WatakeStickyActionBar<Content: View>: View {
    private let content: Content

    /// - Parameter content: The view to present inside the action bar.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(WatakeColor.border.subtle)

            content
                .padding(.horizontal, WatakeSpacing.md)
                .padding(.vertical, WatakeSpacing.sm)
                .background(WatakeColor.surface.base)
        }
        .accessibilityElement(children: .contain)
    }
}
