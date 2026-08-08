//
//  watakeTests.swift
//  watakeTests
//

import ArchiveServices
import CoreGraphics
import DocumentSearchFeature
import Foundation
import Security
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

@MainActor
struct TagFilterTests {
    /// Builds a `LibraryStore` backed by a per-test Application Support
    /// subdirectory and keychain service (via `LibraryStore`'s test-only
    /// initializer), so this suite never reads or writes the real app
    /// archive and never accumulates data across runs. `body` is always
    /// followed by teardown, even if an assertion throws mid-test, since
    /// this is deterministic do/catch/rethrow rather than a `Task` in
    /// `defer` (which would not block test completion).
    private func withIsolatedStore(_ body: (LibraryStore) async throws -> Void) async throws {
        let id = UUID().uuidString
        let subdirectory = "WatakeTests-\(id)"
        let keychainService = "com.watake.tests.\(id)"
        let store = LibraryStore(storageSubdirectory: subdirectory, keychainService: keychainService)
        do {
            try await body(store)
        } catch {
            eraseIsolatedStore(subdirectory: subdirectory, keychainService: keychainService)
            throw error
        }
        eraseIsolatedStore(subdirectory: subdirectory, keychainService: keychainService)
    }

    private func eraseIsolatedStore(subdirectory: String, keychainService: String) {
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(subdirectory, isDirectory: true))
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(query as CFDictionary)
    }

    @Test func filterReturnsOnlyMatchingDocumentsAndClearingRestoresFullOrder() async throws {
        try await withIsolatedStore { store in
            guard let folder = await store.createFolder(name: "Filter test") else {
                Issue.record("Could not create folder")
                return
            }
            let tagged = try #require(
                await store.createTag(label: "Filter tag", colorHex: ArchiveTagPalette.colors[0])
            )
            guard await store.save(
                pages: [ImportedPage(sourceData: Data([0x01]))], grouping: .oneDocument, folder: folder, name: "Tagged"
            ) else {
                Issue.record("Could not save tagged document")
                return
            }
            guard await store.save(
                pages: [ImportedPage(sourceData: Data([0x02]))], grouping: .oneDocument, folder: folder, name: "Untagged"
            ) else {
                Issue.record("Could not save untagged document")
                return
            }

            let originalOrder = store.documents(in: folder)
            #expect(originalOrder.count == 2)
            let taggedDocument = try #require(originalOrder.first { $0.name == "Tagged" })
            _ = await store.assign(tagIds: [tagged.id], document: taggedDocument)

            store.setTagFilter(tagged)
            let filtered = store.filteredDocuments(in: folder)
            #expect(filtered.map(\.id) == [taggedDocument.id])

            store.setTagFilter(nil)
            let cleared = store.filteredDocuments(in: folder)
            #expect(cleared.map(\.id) == store.documents(in: folder).map(\.id))
            #expect(cleared.count == 2)
        }
    }

    @Test func filterDoesNotAffectFolderCountAccessor() async throws {
        try await withIsolatedStore { store in
            guard let folder = await store.createFolder(name: "Filter count test") else {
                Issue.record("Could not create folder")
                return
            }
            let tag = try #require(
                await store.createTag(label: "Count tag", colorHex: ArchiveTagPalette.colors[1])
            )
            guard await store.save(
                pages: [ImportedPage(sourceData: Data([0x03]))], grouping: .oneDocument, folder: folder, name: "Only document"
            ) else {
                Issue.record("Could not save document")
                return
            }

            let countBeforeFilter = store.documents(in: folder).count
            store.setTagFilter(tag)
            #expect(store.documents(in: folder).count == countBeforeFilter)
            #expect(store.filteredDocuments(in: folder).isEmpty)
        }
    }
}
