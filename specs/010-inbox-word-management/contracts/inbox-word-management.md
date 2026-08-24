# Contract: Inbox Word Management & Learn Session Control

**Feature**: 010-inbox-word-management  
**Date**: 2025-07-25  
**Type**: Repository extensions + Data model extension + View interaction contracts

---

## Overview

This contract defines:

1. **`VocabularyEntry` extension** — `isMastered` boolean field (migration `v6`).
2. **Migration `v6`** — `isMastered` column.
3. **New `VocabularyEntryRepository` methods** — `fetchLearnPool()`, `markMastered(id:)`, `deleteAll(ids:)`.
4. **`FocusSession` extension** — `isOnDemand` flag.
5. **View contracts** — Inbox selection mode, Add to Learn, Restart Session, mastery on Easy.

---

## `VocabularyEntry` — `isMastered` field

```swift
extension VocabularyEntry {
    var isMastered: Bool   // migration v6; default false
}
```

| # | Contract |
|---|----------|
| C-01 | `isMastered` is a non-optional `Bool` with a database default of `false` (`0`). |
| C-02 | `VocabularyEntry.CodingKeys` gains `case isMastered = "isMastered"`. |
| C-03 | `isMastered = true` does not change `triageStatus`. The entry remains `'saved'` and visible in vocabulary views. |
| C-04 | `isMastered = true` does not stop future SRS field updates. If the entry is included in an on-demand session and rated, `applyRating` still runs normally. The mastery flag is not cleared by any rating — it can only be set, never unset, in this iteration. |
| C-05 | `isMastered` is the authoritative signal for queue exclusion. `srsState` is not used for this purpose. |

---

## Migration v6

| # | Contract |
|---|----------|
| C-06 | Migration `"v6"` is registered in `Database.migrate()` immediately after `"v5"`. |
| C-07 | It executes: `ALTER TABLE vocabulary_entries ADD COLUMN isMastered INTEGER NOT NULL DEFAULT 0` |
| C-08 | The migration is additive and non-destructive. No existing column is modified or removed. |
| C-09 | Existing rows have `isMastered = 0` after migration. |
| C-10 | Tests use `Database(path: ":memory:")` — the in-memory path triggers all migrations including `v6`. A dedicated `DatabaseMigrationV6Tests` smoke-test verifies the column exists and defaults to `0`. |

---

## `VocabularyEntryRepository` — `fetchLearnPool()`

```swift
/// All saved, non-mastered entries eligible for a Restart Learn session.
/// Ordered by dueDate ascending (overdue-first).
func fetchLearnPool() throws -> [VocabularyEntry]
```

| # | Contract |
|---|----------|
| C-11 | `fetchLearnPool()` filters `triageStatus = 'saved'` AND `isMastered = false`. |
| C-12 | It orders results by `dueDate` ascending (same as `fetchDueEntries`). |
| C-13 | It is synchronous and reads from `dbQueue`. |
| C-14 | Entries with any `srsState` are included (new, learning, known, mastered-via-algorithm) as long as `isMastered = false`. |
| C-15 | This query is broader than `fetchDueEntries`: it does not apply a `dueDate ≤ today` filter. |
| C-16 | An empty result means the Restart empty state should be shown. |

---

## `VocabularyEntryRepository` — `markMastered(id:)`

```swift
/// Sets isMastered = true for the entry with the given id.
/// Issues a single UPDATE touching only the isMastered column.
/// Throws on DB error. Callers must catch.
func markMastered(id: Int64) throws
```

| # | Contract |
|---|----------|
| C-17 | `markMastered(id:)` issues a single `dbQueue.write` UPDATE: `SET isMastered = 1 WHERE id = ?`. |
| C-18 | It does not touch any SRS field, `triageStatus`, `difficultyLabel`, `lastReviewedDate`, or any other column. |
| C-19 | It is `throws`. Unlike `setDifficultyLabel` (fire-and-forget), mastery is a significant state change — callers must not use `try?`. The call site uses `try repository.markMastered(id:)` inside a `do/catch` in the `Task`. On failure, the error is logged; no user-facing indicator is shown (the card advances normally per the existing write-failure path). |
| C-20 | A `ValueObservation` on the entry will fire after this write, removing the word from the queue automatically. |

---

## `VocabularyEntryRepository` — `deleteAll(ids:)`

```swift
/// Hard-deletes all entries whose id is in the provided array.
/// Issues a single write transaction (one ValueObservation fire).
/// Throws on DB error.
func deleteAll(ids: [Int64]) throws
```

| # | Contract |
|---|----------|
| C-21 | `deleteAll(ids:)` executes a single `dbQueue.write` and deletes all matching rows atomically. |
| C-22 | It uses GRDB's key-based batch delete: `try VocabularyEntry.filter(ids: ids).deleteAll(db)` inside the write closure. |
| C-23 | If `ids` is empty, the method is a no-op (issues no SQL). |
| C-24 | It is `throws`. Callers use `Task { try? repository.deleteAll(ids:) }` (delete failure is silent — the list will not update but the entries are still in the DB; the user can retry by trying to delete again). |
| C-25 | Because it wraps all deletes in a single write transaction, `ValueObservation` fires exactly once after the full batch is committed. |

---

## `FocusSession` — `isOnDemand` field

```swift
struct FocusSession {
    // ... existing fields ...
    let isOnDemand: Bool  // true = constructed from Inbox promotion; false = SRS daily queue
}
```

| # | Contract |
|---|----------|
| C-26 | `isOnDemand` is a `let` (immutable) field set once at initialisation. |
| C-27 | For sessions started from "Start Today's Review" (SRS queue), `isOnDemand = false`. |
| C-28 | For sessions started from "Add to Learn" (Inbox promotion), `isOnDemand = true`. |
| C-29 | `isOnDemand` has no effect on session mechanics (`advance`, `appendRetry`, `recordRating`). It is used only by `LearnView` to label the session header and to inform Restart behaviour. |
| C-30 | All existing contracts for `FocusSession` (C-06 through C-15 in contract 009) remain in force. |

---

## `fetchDueEntries()` — updated filter

| # | Contract |
|---|----------|
| C-31 | `fetchDueEntries()` gains an additional filter: `isMastered = false`. The full filter is `triageStatus = 'saved'` AND `dueDate ≤ today` AND `isMastered = false`. |
| C-32 | This change is additive. All existing callers receive mastered-entry exclusion automatically. No code changes required at call sites. |
| C-33 | `fetchDueCount()` gains the same `isMastered = false` filter, keeping the daily progress bar and session header count consistent. |

---

## View Contracts: Inbox Selection Mode

| # | Contract |
|---|----------|
| C-34 | `VocabularyListView` (or its Inbox tab content) holds `@State private var isSelecting: Bool = false` and `@State private var selectedIDs: Set<Int64> = []`. |
| C-35 | A **Select** button in the toolbar/header activates selection mode (`isSelecting = true`). When `isSelecting = true`, the button is replaced by a **Cancel** button. |
| C-36 | In selection mode, each row in the Inbox list renders a checkbox overlay. Tapping a row toggles its ID in `selectedIDs`. |
| C-37 | **Delete Selected** is shown in the toolbar only when `isSelecting = true`. It is disabled when `selectedIDs.isEmpty`. |
| C-38 | Tapping **Delete Selected** calls `Task { try? repository.deleteAll(ids: Array(selectedIDs)) }`, then resets `isSelecting = false` and `selectedIDs = []`. |
| C-39 | **Add to Learn** is shown in the toolbar only when `isSelecting = true`. It is disabled when `selectedIDs.isEmpty`. |
| C-40 | Tapping **Add to Learn**: (1) collects the `VocabularyEntry` objects whose IDs are in `selectedIDs` from the current `entries` array, (2) constructs a `FocusSession(totalCards: selected.count, cards: selected, ratedCount: 0, tally: .init(), failedCardIDs: [], isOnDemand: true)`, (3) assigns it to the `$session` binding passed down from `VocabularySidebarView`, (4) navigates to the Learn tab by setting `selectedTab = .learn` on the parent (via a callback or binding), (5) resets `isSelecting = false` and `selectedIDs = []`. |
| C-41 | Tapping **Cancel** sets `isSelecting = false` and `selectedIDs = []`. No database write occurs. |
| C-42 | If a new entry arrives (via `ValueObservation`) while selection mode is active, it appears in the list without a pre-selected checkbox. |
| C-43 | The Inbox tab does not observe `isMastered` — mastered words are only excluded from Learn sessions, not from the Inbox list. The Inbox shows all `triageStatus = 'unreviewed'` entries regardless of mastery state. |

---

## View Contracts: Add to Learn Navigation

| # | Contract |
|---|----------|
| C-44 | `VocabularySidebarView` exposes a mechanism for `VocabularyListView` to request a tab switch to `.learn`. Implemented via a callback closure `onNavigateToLearn: (() -> Void)?` passed into `VocabularyListView`, which the sidebar calls to set `selectedTab = .learn`. |
| C-45 | The `$session` binding flows: `VocabularySidebarView` (owns `@State var focusSession: FocusSession?`) → passed as `Binding<FocusSession?>` to `VocabularyListView` (new parameter) and as existing binding to `LearnView`. |
| C-46 | When **Add to Learn** creates a new session and the existing `session` is non-nil (a paused session exists), it is silently overwritten. No confirmation dialog is shown. |

---

## View Contracts: Mastery on Easy Rating

| # | Contract |
|---|----------|
| C-47 | When `submitRating(card:rating:)` in `LearnView` receives `rating == .easy` and the `applyRating` write succeeds: after calling `session.recordRating(.easy)` and `session.advance()`, an additional call is made: `try repository.markMastered(id: card.id!)`. |
| C-48 | If `markMastered` throws, the error is logged but no user-facing indicator is shown. The session continues normally. The card has already been advanced. |
| C-49 | `markMastered` is NOT called for `.easy` ratings in Review mode. Mastery is only triggered from Learn mode (the spec requirement is "rating Easy in a Learn session"). |
| C-50 | A mastered entry is visually distinguished in the vocabulary list by showing a "Mastered" label or checkmark badge. The exact visual form is at the implementer's discretion; it must be present and distinguishable without opening the entry. |

---

## View Contracts: Restart Session

| # | Contract |
|---|----------|
| C-51 | `SessionCompletionView` gains a **Restart Session** button alongside the existing **Done** button. |
| C-52 | `LearnView`'s idle state (when `dueEntries` is not empty but no session is active) also gains a **Restart Session** button (or the existing "Start Today's Review" button handles both cases). |
| C-53 | Tapping **Restart Session** calls `repository.fetchLearnPool()` (or equivalent), applies random sampling if needed, and constructs a new `FocusSession`. |
| C-54 | **Random sampling rule**: if `pool.count > 20`, call `pool.shuffled().prefix(20)` to produce the session cards. If `pool.count ≤ 20`, use all entries unchanged (preserving `dueDate` ordering). |
| C-55 | The new `FocusSession` for a Restart has `isOnDemand = false` (it is an SRS-pool-based session, regardless of what the previous session was). |
| C-56 | If `fetchLearnPool()` returns an empty array, the Restart action shows the empty state view. |
| C-57 | The Restart write path is: `Task { let pool = try? repository.fetchLearnPool(); /* sample and build session on @MainActor */ }`. The `fetchLearnPool` call is inside a `Task` to avoid blocking the main thread. |

---

## Threading Contracts

| # | Contract |
|---|----------|
| C-58 | All selection state mutations (`isSelecting`, `selectedIDs`) occur on `@MainActor` (they are `@State` fields in a SwiftUI view). |
| C-59 | `deleteAll(ids:)` is called inside `Task { try? repository.deleteAll(ids:) }` from the `@MainActor` view action handler. |
| C-60 | `markMastered(id:)` is called inside the existing `Task { ... }` in `submitRating(card:rating:)`, after the `applyRating` call succeeds, before advancing to the next card. All three operations (`applyRating`, `markMastered`, `session.recordRating`, `session.advance`) are coordinated within the same `Task`. |
| C-61 | `fetchLearnPool()` is called inside a `Task` from the Restart action. Results are dispatched back to `@MainActor` for session assignment. |
| C-62 | All existing threading contracts from Epic 4 (C-59 through C-62 in contract 009) remain in force. |
