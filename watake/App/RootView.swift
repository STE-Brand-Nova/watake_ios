//
//  RootView.swift
//  watake
//

import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Adaptive app shell: composition and routing only. Chooses between the
/// compact tab shell and the regular sidebar shell from the available
/// container width (never `UIScreen.main.bounds`), per `RESPONSIVE.md`.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    @State private var library = LibraryStore()

    var body: some View {
        GeometryReader { proxy in
            if AppShellLayout.usesSidebar(forWidth: proxy.size.width) {
                RegularSidebarShell(router: router, library: library)
            } else {
                CompactTabShell(router: router, library: library)
            }
        }
        .task {
            await library.purgeExpiredTrash()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await library.purgeExpiredTrash()
                }
            } else if newPhase == .background {
                performBackgroundPurge()
            }
        }
    }

    private func performBackgroundPurge() {
        #if canImport(UIKit)
            var taskId: UIBackgroundTaskIdentifier = .invalid
            var purgeTask: Task<Void, Never>?

            taskId = UIApplication.shared.beginBackgroundTask(withName: "WatakeTrashPurge") {
                purgeTask?.cancel()
                if taskId != .invalid {
                    UIApplication.shared.endBackgroundTask(taskId)
                    taskId = .invalid
                }
            }
            purgeTask = Task {
                await library.purgeExpiredTrash()
                if taskId != .invalid {
                    UIApplication.shared.endBackgroundTask(taskId)
                    taskId = .invalid
                }
            }
        #else
            Task {
                await library.purgeExpiredTrash()
            }
        #endif
    }
}

#Preview {
    RootView()
}
