//
//  ContentView.swift
//  watake
//
//  Created by mbairm3 on 23/07/26.
//

import DesignSystem
import SwiftUI

/// Temporary tokenized root placeholder. Replaces the generated SwiftData Item
/// screen so nothing user-visible bypasses DesignSystem. The real app shell and
/// feature routes arrive in later slices.
struct ContentView: View {
    var body: some View {
        WatakeEmptyState(
            systemImage: "doc.text.magnifyingglass",
            title: "Watake",
            message: "Your local-first document workspace is being set up."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatakeColor.surface.base)
    }
}

#Preview {
    ContentView()
}
