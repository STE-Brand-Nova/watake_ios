//
//  AppRouter.swift
//  watake
//

import Observation

/// Single source of navigation-selection state, shared by the compact tab
/// shell and the regular sidebar shell so switching layouts never resets the
/// selected destination.
@Observable
final class AppRouter {
    var selection: AppDestination

    init(selection: AppDestination = .library) {
        self.selection = selection
    }
}
