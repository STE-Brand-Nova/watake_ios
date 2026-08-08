//
//  watakeTests.swift
//  watakeTests
//

import CoreGraphics
import DocumentSearchFeature
import Foundation
import Testing
import WatakeDomain
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

@MainActor
struct CaptureSaveStateTests {
    @Test func failedSaveRetainsReviewPages() {
        #expect(CaptureSaveState.pagesAfterSave([1, 2], succeeded: false) == [1, 2])
    }

    @Test func successfulSaveClearsReviewPages() {
        #expect(CaptureSaveState.pagesAfterSave([1, 2], succeeded: true).isEmpty)
    }
}

@MainActor
struct CaptureIntegrationTests {
    @Test func storeConformsToCapturePorts() async {
        let store = LibraryStore()
        let activeFolders = await store.activeFolders()
        #expect(activeFolders.isEmpty == store.activeFolders.isEmpty)
    }
}

@MainActor
struct SearchRoutingTests {
    @Test func leavingSearchDestinationResetsVisibleQueryAndState() {
        let router = AppRouter()
        let store = LibraryStore()
        router.selection = .search
        store.searchModel.updateQuery("synthetic")

        #expect(store.searchModel.query == "synthetic")
        #expect(store.searchModel.state == .loading)

        router.selection = .library
        store.resetSearch()

        #expect(router.selection == .library)
        #expect(store.searchModel.query.isEmpty)
        #expect(store.searchModel.state == .emptyQuery)
    }

    @Test func documentSearchResultOpensOwningFolderAndViewer() {
        let store = LibraryStore()
        let folderID = UUID()
        let documentID = UUID()
        let result = ArchiveSearchResult.document(DocumentSearchResult(
            id: documentID,
            folderID: folderID,
            name: "Synthetic document",
            matchCategories: [.ocr]
        ))

        store.openSearchResult(result)

        #expect(store.selectedFolderID == folderID)
        #expect(store.selectedDocumentID == documentID)
    }

    @Test func folderSearchResultOpensFolderWithoutViewer() {
        let store = LibraryStore()
        let folderID = UUID()

        store.openSearchResult(.folder(FolderSearchResult(id: folderID, name: "Synthetic folder", colorHex: "#3B82F6")))

        #expect(store.selectedFolderID == folderID)
        #expect(store.selectedDocumentID == nil)
    }
}
