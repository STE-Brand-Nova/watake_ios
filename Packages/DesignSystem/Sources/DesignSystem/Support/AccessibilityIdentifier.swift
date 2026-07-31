import SwiftUI

extension View {
    /// Applies an accessibility identifier only when the caller supplies one.
    ///
    /// DesignSystem components take an optional `accessibilityIdentifier` and
    /// forward it here. A generic component must not stamp a single shared
    /// identifier (e.g. `"watake.iconButton"`) on every instance — that makes
    /// UI-test lookups ambiguous. Features derive a unique identifier from their
    /// semantic/domain model and pass it in.
    @ViewBuilder
    public func watakeAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
