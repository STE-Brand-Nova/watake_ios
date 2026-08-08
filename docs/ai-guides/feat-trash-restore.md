# AI implementation guide — `feat-trash-restore`

Use this as the implementation prompt for Backlog 11’s second PR. It was
written against the current iOS app, which already contains the first tag PR’s
uncommitted work. Finish and merge `feat/document-tags` before branching this
PR; do not mix the two feature diffs.

## Copy-ready prompt

```text
You are the senior iOS engineer implementing `feat/trash-restore` for Watake.
Deliver one focused, production-quality iOS/iPadOS PR. Start from `main` after
the document-tags PR has merged. Do not include uncommitted tag work, commit,
push, publish, alter signing, or change unrelated features.

Read the repository contribution guide, PR template, lint configuration, and
the supplied Watake product brief, design, responsive, data-model, parity, and
operations documents before editing.

## Inspect before changing

This is a completion PR, not a greenfield trash system. Current code already
has important foundations:

- `StoredDocument.deletedAt` and `Folder.deletedAt` are persisted local-first
  metadata; document assets must remain untouched by soft deletion.
- `ArchiveService` already moves documents/folders to Trash, restores them,
  preserves a document’s `folderId`, and exposes
  `retentionDaysRemaining(deletedAt:now:)`.
- Folder deletion is a folder tombstone: do not write a tombstone to every
  child. Restoring the folder makes its non-trashed children visible again;
  independently trashed documents stay trashed.
- `LibraryStore` exposes basic trash/restore intents.
- `TrashView` already lists basic rows. Extend it rather than adding a second
  trash surface.

Preserve the encrypted `WatakeFileStorage` boundary. Do not add SwiftData,
remote telemetry, cloud sync, permanent-delete UI, automatic purge, or bulk
trash management in this PR.

## Outcome

Users can soft-delete a document or folder, immediately undo the most recent
deletion, open Trash, see a clear remaining-retention message, and restore an
item safely to its original location. Every mutation goes through
`ArchiveService`; SwiftUI views do not access storage directly.

## Required behavior

### 1. Soft deletion

- Deleting a document immediately sets `deletedAt`, preserves its immutable
  ID, original `folderId`, pages, tag IDs, watermark reference, and assets, and
  removes it from active library/search results.
- Deleting a folder immediately sets only that folder’s `deletedAt`. Its active
  children are hidden because their owner is trashed, not because each child is
  rewritten. A document that was already independently trashed remains so.
- A failed deletion changes neither visible data nor undo state. Return a
  success/result from `LibraryStore` where the UI needs to know whether a
  mutation succeeded; do not dismiss or show Undo optimistically.

### 2. Restore to the original folder

- Restoring a document clears only its `deletedAt`; it must retain its original
  `folderId` and all associated metadata/assets.
- Restore a document only when its original folder still exists and is active.
  If the folder is missing or in Trash, keep the document in Trash and show a
  concise recovery message without including a document name, folder name,
  path, or raw storage error.
- Restoring a folder clears only that folder’s tombstone. Its non-trashed
  children reappear naturally. Do not accidentally restore documents that had
  their own `deletedAt` before the folder was trashed.

### 3. Undo recent deletion

- After a successful Library deletion, show a single in-session Undo banner
  above the adaptive Library content. Use one pending item at a time; a new
  deletion replaces and cancels the previous Undo offer.
- The deletion is still persisted immediately. Undo restores the item by ID;
  it is not a delayed delete and never permanently deletes data.
- Keep Undo available for 5 seconds. Model expiry with structured concurrency,
  cancellation, and an injected/testable duration or sleeper. Do not use an
  unowned `Timer`, `DispatchQueue.asyncAfter`, or a task that can clear a newer
  undo offer.
- Clear the banner after a successful undo or expiry. If undo fails, preserve
  the current archive state, show a privacy-safe error, and do not falsely
  report restoration.
- The pending Undo state is session-only. It does not need to survive app
  termination/backgrounding; the item remains safely in Trash.

### 4. Trash presentation and retention time

- Keep one `TrashView` destination. Use clear sections or type labels for
  folders and documents. A document row shows its original folder only when
  that folder is locally available; a folder row identifies itself as a folder
  rather than claiming an original location.
- Each row has a 44pt Restore action, a VoiceOver label/hint, Dynamic Type-safe
  layout, and semantic DesignSystem colors/tokens only.
- Render retention from `ArchiveService.retentionDaysRemaining`, using a small
  pure presentation helper rather than recalculating dates in a view:
  `30 days remaining`, `1 day remaining`, and `Expires today` for zero. Avoid
  stale captured dates by deriving it during render/refresh.
- Keep the existing empty state when no trash items exist. Add a recovery alert
  to Trash itself so a failed restore is visible even when the user is not on
  the Library screen.
- Support iPhone and iPad from available container width. Do not use device or
  screen-size checks. Respect 44pt targets, keyboard/focus behavior, VoiceOver,
  Dark Mode, and reduced motion.

## Architecture boundaries

- Keep business invariants and typed errors in `ArchiveService`.
- Keep `LibraryStore` as `@MainActor @Observable` presentation state. It owns
  the active undo item, cancellation/generation protection, and view-facing
  success/failure intents.
- Keep `TrashView` and the undo banner declarative: render store state and
  forward actions only. Do not read encrypted records or make persistence calls
  from a view.
- Put any reusable ephemeral undo model in a focused app/domain value type; do
  not introduce a generic command framework or a large new package for one
  action.
- Never log document names, folder names, OCR text, file paths, or raw errors.
  Do not add remote analytics/telemetry.

## Expected change boundaries

Prefer a focused diff in these ownership points:

- `Packages/ArchiveServices/.../ArchiveService.swift` and its tests for
  tombstone/restore invariants and retention boundaries.
- `watake/App/LibraryStore.swift` for mutation results and session-only undo
  state; add a narrow test seam for the expiry clock/sleeper if needed.
- `watake/App/LibraryViews.swift` or a small focused undo-banner view for the
  Library-facing action.
- `watake/App/TrashView.swift` for truthful rows, restore feedback, and
  retention presentation.
- Existing package and app tests. Do not change the serialized data-model
  contract: `deletedAt` and original `folderId` already supply this PR.

## Required tests

Add or update deterministic tests for all of the following:

1. document soft deletion preserves ID, original folder, pages, tags, and asset
   references; active/library and search queries hide it;
2. restoring a document puts it back in the same active folder with the same
   metadata and data survives an encrypted-storage reload;
3. restoring a document fails when the original folder is missing or trashed,
   and leaves the document trashed;
4. folder tombstone/restore hides and restores ordinary children without
   changing independently trashed child documents;
5. retention-day boundaries produce 30, 1, and 0 days deterministically from
   an injected/fixed `now` value;
6. a successful document and folder deletion each create an undo offer; Undo
   restores the intended ID; a failed deletion creates no undo offer;
7. a newer deletion replaces the earlier offer, an expired/cancelled task
   cannot clear the newer offer, and undo failure does not claim success;
8. the Trash presentation’s `1 day`/plural/`Expires today` text is correct;
9. manual iPhone and iPad checks cover deletion, Undo, Trash restore, original
   folder unavailable, large Dynamic Type, VoiceOver, and Dark Mode.

Use isolated temporary storage/keychain identifiers for app tests. Do not leave
soft-deleted folders, documents, tags, assets, or pending data in the shared
Application Support test archive.

Run narrow tests first, then:

```sh
swiftformat --lint . --config .swiftformat
swiftlint lint --strict --no-cache --config .swiftlint.yml
bundle exec fastlane test
```

If a simulator is unavailable, report that clearly and run every available
non-simulator check. Never weaken linting or skip tests to make the PR pass.

## Definition of done

- Document and folder deletion are durable soft deletes, never asset deletion.
- Undo is immediate, single-item, session-only, time-bounded, and race-safe.
- Restore respects original-folder availability and preserves independent
  child-document tombstones.
- Trash gives clear remaining-retention wording and a visible restore failure
  path on iPhone and iPad.
- No permanent deletion, automatic purge, bulk actions, cloud changes, or
  unrelated tag work is included.
- Formatter, linter, and the available Fastlane suite pass.
- The PR uses the repository template with iPhone/iPad screenshots, a concise
  release note, and a parent-repository `docs/PARITY.md` follow-up that records
  the resulting iOS PR/commit evidence. Do not claim Android parity without an
  Android implementation.
```

