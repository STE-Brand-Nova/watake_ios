//
//  RegularSidebarShell.swift
//  watake
//

import SwiftUI

/// Sidebar shell for available content width 700pt and above.
/// Declaration order in `AppDestination` puts Capture near the top.
struct RegularSidebarShell: View {
    @Bindable var router: AppRouter
    @Bindable var library: LibraryStore

    var body: some View {
        NavigationSplitView {
            List(AppDestination.allCases, selection: selectionBinding) { destination in
                Label(destination.label, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("Watake")
        } detail: {
            NavigationStack {
                DestinationRootView(destination: router.selection, library: library)
            }
        }
    }

    /// `List` selection needs an optional binding; the router's selection
    /// stays the single non-optional source of truth. Deselection (`nil`) is
    /// ignored so a destination is always shown.
    private var selectionBinding: Binding<AppDestination?> {
        Binding(
            get: { router.selection },
            set: { newValue in
                if let newValue {
                    router.selection = newValue
                }
            }
        )
    }
}
