//
//  AppShellLayout.swift
//  watake
//

import DesignSystem
import Foundation

/// Pure width-to-shell decision, kept separate from `RootView` so the
/// compact/regular boundary is unit-testable without instantiating SwiftUI.
enum AppShellLayout {
    /// `true` for `WatakeLayout` regular/expanded widths (>= 700pt): use the
    /// sidebar shell. `false` for compact widths: use the tab shell.
    static func usesSidebar(forWidth width: CGFloat) -> Bool {
        WatakeLayout.widthClass(for: width) != .compact
    }
}
