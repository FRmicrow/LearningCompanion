# Contract: Learn & Review Sessions

**Feature**: 009-learn-review-sessions  
**Date**: 2025-07-23  
**Type**: View contracts + Service/state contracts + Repository extension + Data model extension

---

## Overview

This contract defines:

1. **`DifficultyLabel`** — persisted enum for user difficulty annotation.
2. **`FocusSession`** — in-memory value type managing session state.
3. **`FocusSession.RatingTally`** — nested tally type.
4. **`SRSUpdate` extension** — `lastReviewedDate` field added (Epic 3 type extended here).
5. **New `VocabularyEntryRepository` method** — `setDifficultyLabel(id:label:)`.
6. **Extended `applyRating(id:update:)`** — writes `lastReviewedDate` in the same transaction.
7. **`VocabularyEntry` extension** — two new optional fields.
8. **Migration `v5`** — two new nullable columns on `vocabulary_entries`.
9. **View interaction contracts** — `LearnView`, `ReviewView`, `FocusSession` lifecycle rules.

---

## `DifficultyLabel`

```swift
enum DifficultyLabel: String, Codable {
    case easy   = "easy"
    case medium = "medium"
    case hard   = "hard"
}
```

| # | Contract |
|---|----------|
| C-01 | `DifficultyLabel` is a top-level type (not nested in `VocabularyEntry`). |
| C-02 | Raw string values match the SQL values stored in the `difficultyLabel` column. |
| C-03 | `DifficultyLabel` is `Codable` to support GRDB persistence. |
| C-04 | `DifficultyLabel` is **not** passed to `SRSEngine.rate(_:rating:)`. It is a user annotation only. |
| C-05 | A `nil` `difficultyLabel` on `VocabularyEntry` means the user has never set a difficulty for that entry. The card selector renders with no option pre-selected. |

---

## `FocusSession`

```swift
struct FocusSession {
    let totalCards:    Int
    var cards:         [VocabularyEntry]
    var ratedCount:    Int
    var tally:         RatingTally
    var failedCardIDs: Set<Int64>

    var isComplete: Bool { cards.isEmpty }
    var current:    VocabularyEntry? { cards.first }

    mutating func advance()
    mutating func appendRetry(_ entry: VocabularyEntry)
    mutating func recordRating(_ rating: SRSRating)

    struct RatingTally {
        var again: Int = 0
        var hard:  Int = 0
        var good:  Int = 0
        var easy:  Int = 0
    }
}
```

| # | Contract |
|---|----------|
| C-06 | `FocusSession` is a value type (struct). It is held in `@State` on the sidebar tab container view. |
| C-07 | `totalCards` is set once at session initialisation from the count of the captured queue snapshot. It never changes during the session, even when retry cards are appended. |
| C-08 | `cards` contains the ordered list of unrated entries remaining in the session. The first element is always the current card. |
| C-09 | `advance()` removes `cards[0]`. It does not modify `ratedCount` or `tally`. |
| C-10 | `recordRating(_ rating:)` increments the corresponding field on `tally` and increments `ratedCount` by 1. It is called only after a **successful** write. |
| C-11 | `appendRetry(_ entry:)` appends the entry to the end of `cards` **only if** `entry.id` is not already in `failedCardIDs`. It then inserts `entry.id` into `failedCardIDs`. |
| C-12 | If `entry.id` is already in `failedCardIDs` when `appendRetry` is called, the entry is not appended and `failedCardIDs` is not modified. This enforces the single-retry rule. |
| C-13 | `isComplete` returns `true` when `cards` is empty. This is the signal to show `SessionCompletionView`. |
| C-14 | `FocusSession` is not persisted to disk. It lives only in memory for the lifetime of the app session. On app restart, the session is not restored. |
| C-15 | Session state is preserved across tab switches because the `@State` variable lives on the parent container view, which is never deallocated while the sidebar is open. |

---

## `FocusSession.RatingTally`

| # | Contract |
|---|----------|
| C-16 | `RatingTally` is a value type nested inside `FocusSession`. It is not persisted. |
| C-17 | All four fields (`again`, `hard`, `good`, `easy`) start at `0` when a new session is initialised. |
| C-18 | The tally is passed to `SessionCompletionView` for display. No database query is needed to retrieve it. |

---

## `SRSUpdate` Extension (Epic 3 type)

```swift
struct SRSUpdate {
    let srsState:         SRSState
    let dueDate:          String    // "YYYY-MM-DD"
    let interval:         Double
    let easeFactor:       Double
    let ratingCount:      Int
    let lastReviewedDate: String    // "YYYY-MM-DD" — added in Epic 4
}
```

| # | Contract |
|---|----------|
| C-19 | `lastReviewedDate` is added to `SRSUpdate`. Its value is always today's date string in `YYYY-MM-DD` format, computed by `SRSEngine.rate(_:rating:)` at call time using `Calendar.current`. |
| C-20 | Adding `lastReviewedDate` to `SRSUpdate` is additive and non-breaking. All existing `SRSEngine` callers (Epic 3 tests, `applyRating`) must be updated to supply or consume the new field. |
| C-21 | `SRSEngine.rate(_:rating:)` sets `lastReviewedDate = todayString` (same computation as `dueDate` — `Calendar.current`, `yyyy-MM-dd` format). |

---

## `VocabularyEntry` Extension (migration v5)

```swift
extension VocabularyEntry {
    var difficultyLabel:   DifficultyLabel?   // stored field
    var lastReviewedDate:  String?            // stored field, "YYYY-MM-DD"
}
```

| # | Contract |
|---|----------|
| C-22 | Both new fields are optional (nullable DB columns). |
| C-23 | `VocabularyEntry.CodingKeys` is extended with two new cases: `difficultyLabel = "difficultyLabel"`, `lastReviewedDate = "lastReviewedDate"`. |
| C-24 | Migration `v5` adds both columns with `DEFAULT NULL` (no `NOT NULL` constraint). |
| C-25 | Existing rows (inserted before `v5`) have both new fields as `NULL`. |
| C-26 | `DifficultyLabel` is decoded from the `difficultyLabel` column. A nil value means no difficulty has been set. |

---

## `VocabularyEntryRepository` — New Method

```swift
/// Persists the user-selected difficulty label for the given entry.
/// Issues a single UPDATE touching only the `difficultyLabel` column.
/// Throws on DB error. Callers use `Task { try? ... }` (silent failure acceptable).
func setDifficultyLabel(id: Int64, label: DifficultyLabel) throws
```

| # | Contract |
|---|----------|
| C-27 | `setDifficultyLabel(id:label:)` issues a single `dbQueue.write` UPDATE touching only `difficultyLabel`. |
| C-28 | It does not touch `srsState`, `dueDate`, `interval`, `easeFactor`, `ratingCount`, `lastReviewedDate`, `triageStatus`, or any other column. |
| C-29 | It is `throws`. Callers catch silently (`try?`). No user-facing error is shown for a difficulty write failure. |
| C-30 | It is synchronous. Callers dispatch it via `Task { try? repository.setDifficultyLabel(...) }` from a SwiftUI action handler. |
| C-31 | A `ValueObservation` on the entry will fire after this write — the difficulty selector stays in sync automatically if the card view observes the entry. |

---

## `VocabularyEntryRepository` — Extended `applyRating`

```swift
/// Extended signature (Epic 4 update):
func applyRating(id: Int64, update: SRSUpdate) throws
```

The UPDATE statement is extended to include `lastReviewedDate`:

```sql
UPDATE vocabulary_entries
SET srsState          = ?,
    dueDate           = ?,
    interval          = ?,
    easeFactor        = ?,
    ratingCount       = ?,
    lastReviewedDate  = ?
WHERE id = ?
```

| # | Contract |
|---|----------|
| C-32 | `applyRating` writes all six fields (`srsState`, `dueDate`, `interval`, `easeFactor`, `ratingCount`, `lastReviewedDate`) in a single atomic transaction. |
| C-33 | The `lastReviewedDate` value comes from `update.lastReviewedDate`. |
| C-34 | All prior contracts from Epic 3 (C-33 through C-37, C-42 through C-45) remain in force. |

---

## Migration v5

| # | Contract |
|---|----------|
| C-35 | Migration `v5` is registered in `Database.migrate()` and runs after `v4`. |
| C-36 | It adds two nullable columns: `difficultyLabel TEXT DEFAULT NULL`, `lastReviewedDate TEXT DEFAULT NULL`. |
| C-37 | The migration is additive and non-destructive. No existing column is modified or removed. |
| C-38 | Existing rows have both new fields as `NULL` after migration. |

---

## View Interaction Contracts

### Reveal / Rating Gate

| # | Contract |
|---|----------|
| C-39 | Rating buttons (`Again` / `Hard` / `Good` / `Easy` in Learn; `Easy` / `Medium` / `Hard` in Review) are rendered only after `isRevealed == true`. Before reveal, they are not present in the view hierarchy. |
| C-40 | The Space keyboard shortcut sets `isRevealed = true`. It is always active on the card view. |
| C-41 | Keyboard shortcut `1`/`2`/`3`/`4` (Learn) and `1`/`2`/`3` (Review) are active only when `isRevealed == true`. Before reveal, pressing these keys has no effect and triggers no write. |
| C-42 | When the user submits a rating (button tap or keyboard shortcut), `isRevealed` is reset to `false` as part of advancing to the next card. |

### Session Lifecycle

| # | Contract |
|---|----------|
| C-43 | A `FocusSession` is initialised with a snapshot of the result of `fetchDueEntries()` at the moment the user taps "Start Today's Review". The queue is not re-queried during the session. |
| C-44 | After a successful rating write: `session.recordRating(rating)` is called, then `session.advance()` is called, then `isRevealed` is reset to `false`. |
| C-45 | After a failed rating write: a transient inline error is shown on the current card. Then `session.appendRetry(currentCard)` is called. Then `session.advance()` is called. `session.recordRating` is **not** called. `isRevealed` is reset to `false`. |
| C-46 | When `session.isComplete == true` after `advance()`, the view transitions to `SessionCompletionView`, passing `session.ratedCount` and `session.tally`. |
| C-47 | `SessionCompletionView` displays: "You reviewed N words" and a breakdown of `tally.again`, `tally.hard`, `tally.good`, `tally.easy`. |
| C-48 | `SessionCompletionView` has a dismiss/close action that resets the session state to `nil` (or equivalent empty state) and returns the tab to its idle state. |

### Difficulty Selector

| # | Contract |
|---|----------|
| C-49 | The difficulty selector is rendered on every card, regardless of `isRevealed` state. |
| C-50 | On tap of a difficulty option, `Task { try? repository.setDifficultyLabel(id: card.id!, label: selected) }` is dispatched immediately. |
| C-51 | The selector pre-selects `card.difficultyLabel` if non-nil. |
| C-52 | Changing the difficulty during a session does not affect session progress, `ratedCount`, or `tally`. |

### Review Metadata Footer

| # | Contract |
|---|----------|
| C-53 | Every card renders a metadata footer regardless of `isRevealed` state. |
| C-54 | "Last review" is computed from `card.lastReviewedDate`: nil → "Never"; today → "Today"; 1 day ago → "Yesterday"; N days ago → "N days ago". |
| C-55 | "Next review" is computed from `card.dueDate`: today or past → "Today"; 1 day in future → "Tomorrow"; N days in future → "In N days". |
| C-56 | Relative date computation uses `Calendar.current` at render time. No UTC conversion is applied. |

### Review Mode Rating Mapping

| # | Contract |
|---|----------|
| C-57 | In Review mode (F-402), the three UI rating labels map to `SRSRating` as follows: "Easy" → `.easy`, "Medium" → `.good`, "Hard" → `.hard`. |
| C-58 | The mapping in C-57 is applied before calling `SRSEngine.rate(_:rating:)` and `applyRating`. The SRS engine never receives a "Medium" input — it only sees `.easy`, `.good`, `.hard`, `.again`. |

---

## Threading Contracts

| # | Contract |
|---|----------|
| C-59 | All view state mutations (`isRevealed`, `session`) occur on `@MainActor`. |
| C-60 | `applyRating` is called inside `Task { try repository.applyRating(...) }` from a `@MainActor` view action. On success, `session.recordRating` and `session.advance()` are called via `Task { @MainActor in ... }`. On error, the error path is also dispatched `@MainActor`. |
| C-61 | `setDifficultyLabel` is called inside `Task { try? repository.setDifficultyLabel(...) }`. No main-thread dispatch is needed for the result (fire-and-forget). |
| C-62 | The `ValueObservation` for the daily queue (started in the Learn/Review tab view) follows the established project pattern: `Task { @MainActor in for try await entries in observation.values(in: repository.dbQueue) { ... } }`, cancelled in `.onDisappear`. |
