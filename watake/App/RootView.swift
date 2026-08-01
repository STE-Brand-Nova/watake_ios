//
//  RootView.swift
//  watake
//

import SwiftUI

/// Adaptive app shell: composition and routing only. Chooses between the
/// compact tab shell and the regular sidebar shell from the available
/// container width (never `UIScreen.main.bounds`), per `RESPONSIVE.md`.
struct RootView: View {
    @State private var router = AppRouter()

    var body: some View {
        GeometryReader { proxy in
            if AppShellLayout.usesSidebar(forWidth: proxy.size.width) {
                RegularSidebarShell(router: router)
            } else {
                CompactTabShell(router: router)
            }
        }
    }
}

#Preview {
    RootView()
}
