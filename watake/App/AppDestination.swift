//
//  AppDestination.swift
//  watake
//

import Foundation

/// The five top-level app-shell destinations, per `watake-app-brief.md` §6.
///
/// Declaration order (`allCases`) is the sidebar's source of truth, matching
/// `RESPONSIVE.md` ("Sidebar destinations: Files, Capture, Copies, Trash,
/// Settings") — Capture sits second, near the top. The compact tab bar uses
/// its own `compactTabOrder` so Capture can sit at the literal center
/// instead, independent of the sidebar order.
enum AppDestination: String, CaseIterable, Identifiable, Hashable {
    case library
    case capture
    case copies
    case trash
    case settings

    /// Compact tab-bar order: Capture at index 2, the true center of five
    /// items, so it reads as the primary/prominent action per the brief.
    static let compactTabOrder: [AppDestination] = [.library, .copies, .capture, .trash, .settings]

    var id: String {
        rawValue
    }

    /// User-visible labels follow the product brief's Files/Copies split.
    var label: String {
        switch self {
        case .library: "Files"
        case .capture: "Capture"
        case .copies: "Copies"
        case .trash: "Trash"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "folder"
        case .capture: "camera"
        case .copies: "doc.on.doc"
        case .trash: "trash"
        case .settings: "gearshape"
        }
    }
}
