//
//  CompactTabShell.swift
//  watake
//

import SwiftUI

/// Five-destination shell for available content width below 700pt. Uses
/// `AppDestination.compactTabOrder` so Capture sits at the literal center,
/// independent of the sidebar's order.
///
/// `CompactTabBar` is the only compact-width navigation control. A `TabView`
/// would still create native tab chrome on newer iOS releases, leaving an
/// empty bar above this custom one.
struct CompactTabShell: View {
    @Bindable var router: AppRouter
    @Bindable var library: LibraryStore

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                DestinationRootView(destination: router.selection, library: library)
            }

            CompactTabBar(router: router)
        }
    }
}
