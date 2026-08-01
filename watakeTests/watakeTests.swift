//
//  watakeTests.swift
//  watakeTests
//

import CoreGraphics
import Testing
@testable import watake

@MainActor
struct AppDestinationTests {
    @Test func exactlyFiveDestinations() {
        #expect(AppDestination.allCases.count == 5)
    }

    @Test func stableLabels() {
        #expect(AppDestination.library.label == "Folders")
        #expect(AppDestination.capture.label == "Capture")
        #expect(AppDestination.search.label == "Search")
        #expect(AppDestination.trash.label == "Trash")
        #expect(AppDestination.settings.label == "Settings")
    }

    @Test func captureIsSecondInSidebarOrder() {
        let order = AppDestination.allCases
        #expect(order == [.library, .capture, .search, .trash, .settings])
    }

    @Test func captureIsCenteredInCompactTabOrder() {
        let order = AppDestination.compactTabOrder
        #expect(order.count == 5)
        #expect(order[2] == .capture)
        #expect(Set(order) == Set(AppDestination.allCases))
    }
}

@MainActor
struct AppRouterTests {
    @Test func defaultDestinationIsLibrary() {
        let router = AppRouter()
        #expect(router.selection == .library)
    }

    @Test func selectionPreservedAcrossReads() {
        let router = AppRouter()
        router.selection = .search
        #expect(router.selection == .search)
        router.selection = .trash
        #expect(router.selection == .trash)
    }
}

@MainActor
struct AppShellLayoutTests {
    @Test func compactBelowSevenHundred() {
        #expect(AppShellLayout.usesSidebar(forWidth: 699) == false)
    }

    @Test func sidebarFromSevenHundred() {
        #expect(AppShellLayout.usesSidebar(forWidth: 700) == true)
    }
}
