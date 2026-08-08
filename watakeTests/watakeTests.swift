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

@MainActor
struct TrashRestorePresentationTests {
    private func withIsolatedStore(
        undoDuration: Duration = .seconds(60),
        sleeper: ManualUndoSleeper? = nil,
        _ body: (LibraryStore) async throws -> Void
    ) async throws {
        let id = UUID().uuidString
        let subdirectory = "WatakeTrashTests-\(id)"
        let keychainService = "com.watake.tests.trash.\(id)"
        let undoSleeper: @Sendable (Duration) async throws -> Void
        if let sleeper {
            undoSleeper = { _ in await sleeper.sleep() }
        } else {
            undoSleeper = { duration in try await Task.sleep(for: duration) }
        }
        let store = LibraryStore(
            storageSubdirectory: subdirectory,
            keychainService: keychainService,
            undoDuration: undoDuration,
            undoSleeper: undoSleeper
        )
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
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ] as CFDictionary)
    }

    @Test func documentTrashCreatesUndoAndUndoRestoresIt() async throws {
        try await withIsolatedStore { store in
            guard let folder = await store.createFolder(name: "Trash test") else {
                Issue.record("Could not create folder")
                return
            }
            #expect(await store.save(
                pages: [ImportedPage(sourceData: Data([0x01]))], grouping: .oneDocument, folder: folder, name: "Scan"
            ))
            let document = try #require(store.documents(in: folder).first)

            #expect(await store.trashDocument(document))
            #expect(store.documents(in: folder).isEmpty)
            #expect(store.pendingTrashUndo?.item == .document(document.id))

            #expect(await store.undoTrash())
            #expect(store.pendingTrashUndo == nil)
            #expect(store.documents(in: folder).map(\.id) == [document.id])
        }
    }

    @Test func folderTrashCreatesUndoAndHidesItsActiveChildren() async throws {
        try await withIsolatedStore { store in
            guard let folder = await store.createFolder(name: "Folder trash test") else {
                Issue.record("Could not create folder")
                return
            }
            #expect(await store.save(
                pages: [ImportedPage(sourceData: Data([0x02]))], grouping: .oneDocument, folder: folder, name: "Scan"
            ))

            #expect(await store.trashFolder(folder))
            #expect(store.activeFolders.isEmpty)
            #expect(store.documents(in: folder).isEmpty)
            #expect(store.pendingTrashUndo?.item == .folder(folder.id))
            #expect(await store.undoTrash())
            #expect(store.activeFolders.map(\.id) == [folder.id])
            #expect(store.documents(in: folder).count == 1)
        }
    }

    @Test func failedDeletionDoesNotCreateOrReplaceUndoOffer() async throws {
        try await withIsolatedStore { store in
            guard let folder = await store.createFolder(name: "Failed trash test") else {
                Issue.record("Could not create folder")
                return
            }
            #expect(await store.save(
                pages: [ImportedPage(sourceData: Data([0x03]))], grouping: .oneDocument, folder: folder, name: "Scan"
            ))
            let document = try #require(store.documents(in: folder).first)
            #expect(await store.trashDocument(document))
            let offer = try #require(store.pendingTrashUndo)

            #expect(await store.trashDocument(document) == false)
            #expect(store.pendingTrashUndo == offer)
        }
    }

    @Test func manualRestoreClearsOnlyItsMatchingUndoOffer() async throws {
        try await withIsolatedStore { store in
            guard let folder = await store.createFolder(name: "Manual restore test") else {
                Issue.record("Could not create folder")
                return
            }
            #expect(await store.save(
                pages: [ImportedPage(sourceData: Data([0x06]))], grouping: .oneDocument, folder: folder, name: "First"
            ))
            #expect(await store.save(
                pages: [ImportedPage(sourceData: Data([0x07]))], grouping: .oneDocument, folder: folder, name: "Second"
            ))
            let documents = store.documents(in: folder)
            let first = try #require(documents.first)
            let second = try #require(documents.last)

            #expect(await store.trashDocument(first))
            #expect(await store.trashDocument(second))
            #expect(store.pendingTrashUndo?.item == .document(second.id))

            #expect(await store.restoreDocument(first))
            #expect(store.pendingTrashUndo?.item == .document(second.id))

            #expect(await store.restoreDocument(second))
            #expect(store.pendingTrashUndo == nil)
            #expect(await store.undoTrash() == false)
            #expect(store.errorMessage == nil)
        }
    }

    @Test func newerDeletionCannotBeClearedByCancelledOlderExpiry() async throws {
        let sleeper = ManualUndoSleeper()
        try await withIsolatedStore(sleeper: sleeper) { store in
            guard let folder = await store.createFolder(name: "Expiry test") else {
                Issue.record("Could not create folder")
                return
            }
            #expect(await store.save(
                pages: [ImportedPage(sourceData: Data([0x04]))], grouping: .oneDocument, folder: folder, name: "First"
            ))
            #expect(await store.save(
                pages: [ImportedPage(sourceData: Data([0x05]))], grouping: .oneDocument, folder: folder, name: "Second"
            ))
            let documents = store.documents(in: folder)
            let first = try #require(documents.first)
            let second = try #require(documents.last)

            #expect(await store.trashDocument(first))
            await sleeper.waitForRegistrations(1)
            #expect(await store.trashDocument(second))
            await sleeper.waitForRegistrations(2)

            await sleeper.resumeNext()
            await Task.yield()
            #expect(store.pendingTrashUndo?.item == .document(second.id))

            await sleeper.resumeNext()
            await Task.yield()
            #expect(store.pendingTrashUndo == nil)
        }
    }

    @Test func retentionMessageUsesSingularPluralAndToday() {
        #expect(TrashRetentionText.message(daysRemaining: 30) == "30 days remaining")
        #expect(TrashRetentionText.message(daysRemaining: 1) == "1 day remaining")
        #expect(TrashRetentionText.message(daysRemaining: 0) == "Expires today")
    }
}

private actor ManualUndoSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var registrationWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            let waiters = registrationWaiters
            registrationWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitForRegistrations(_ count: Int) async {
        while continuations.count < count {
            await withCheckedContinuation { continuation in
                registrationWaiters.append(continuation)
            }
        }
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}
