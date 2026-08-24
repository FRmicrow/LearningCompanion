# Data Model: Learn & Review — Sessions de révision

**Feature**: 009-learn-review-sessions  
**Date**: 2025-07-23

---

## Overview

This epic introduces **migration `v5`** that adds two new nullable columns to the existing `vocabulary_entries` table (`difficultyLabel`, `lastReviewedDate`). No new tables are created.

New Swift types introduced:
- `DifficultyLabel` — enum (persisted)
- `FocusSession` — in-memory value type (not persisted)
- `FocusSession.RatingTally` — in-memory nested struct (not persisted)

Epic 3's `SRSUpdate` struct is extended with `lastReviewedDate`.

One new repository method is added (`setDifficultyLabel`). The existing `applyRating` method is extended to also write `lastReviewedDate`.

---

## Schema Change — Migration v5

### `vocabulary_entries` — added columns

| Column | SQL Type | Nullable | Default |
|--------|----------|----------|---------|
| `difficultyLabel` | `TEXT` | YES | `NULL` |
| `lastReviewedDate` | `TEXT` | YES | `NULL` |

Both columns default to `NULL` — no existing entry has a pre-set difficulty or review date.

**SQL** (GRDB `alter` DSL equivalent):
```sql
ALTER TABLE vocabulary_entries ADD COLUMN difficultyLabel   TEXT DEFAULT NULL
ALTER TABLE vocabulary_entries ADD COLUMN lastReviewedDate  TEXT DEFAULT NULL
```

**Migration registration**: Registered as `"v5"` in `Database.migrate()`. Runs after `"v4"` (Epic 3's SRS columns).

---

## Updated Entity — `VocabularyEntry`

### New fields (added in migration v5)

| Field | Swift Type | DB Column | Default |
|-------|-----------|-----------|---------|
| `difficultyLabel` | `DifficultyLabel?` | `difficultyLabel` | `nil` |
| `lastReviewedDate` | `String?` | `lastReviewedDate` | `nil` — format `YYYY-MM-DD` |

Both fields are `Optional`. A `nil` `difficultyLabel` means the user has not set a difficulty for this entry. A `nil` `lastReviewedDate` means the entry has never been successfully rated.

**`CodingKeys` additions** (camelCase → camelCase per project convention):
- `difficultyLabel` → `"difficultyLabel"`
- `lastReviewedDate` → `"lastReviewedDate"`

### Full `VocabularyEntry` field summary (after migration v5)

| Field | Type | Notes |
|-------|------|-------|
| `id` | `Int64?` | Primary key |
| `englishText` | `String` | Source word; `UNIQUE` |
| `frenchTranslation` | `String?` | Nullable until translated |
| `translationStatus` | `TranslationStatus` | `.pending` / `.translated` |
| `triageStatus` | `TriageStatus` | Added in Epic 2 (`v3`) |
| `seenCount` | `Int` | Incremented on duplicate captures |
| `firstCapturedAt` | `Date` | Capture timestamp |
| `lastSeenAt` | `Date` | Last re-capture timestamp |
| `isRetained` | `Bool` | Legacy keep/dismiss flag |
| `srsState` | `SRSState?` | Added in Epic 3 (`v4`) |
| `dueDate` | `String?` | Added in Epic 3 (`v4`) — next review date `YYYY-MM-DD` |
| `interval` | `Double?` | Added in Epic 3 (`v4`) |
| `easeFactor` | `Double?` | Added in Epic 3 (`v4`) |
| `ratingCount` | `Int?` | Added in Epic 3 (`v4`) |
| `difficultyLabel` | `DifficultyLabel?` | **NEW** — user annotation |
| `lastReviewedDate` | `String?` | **NEW** — date of last successful rating (`YYYY-MM-DD`) |

---

## New Enum — `DifficultyLabel`

Top-level type, not nested in `VocabularyEntry`.

```swift
enum DifficultyLabel: String, Codable {
    case easy   = "easy"
    case medium = "medium"
    case hard   = "hard"
}
```

- Raw values match the SQL column values stored in `difficultyLabel`.
- `Codable` to support GRDB persistence.
- Not used by `SRSEngine` — it is never passed to `SRSEngine.rate(_:rating:)`.

---

## Extended Value Type — `SRSUpdate` (Epic 3)

`SRSUpdate` gains one new field so that `applyRating` can write `lastReviewedDate` in the same transaction:

```swift
struct SRSUpdate {
    let srsState:          SRSState
    let dueDate:           String    // "YYYY-MM-DD"
    let interval:          Double
    let easeFactor:        Double
    let ratingCount:       Int
    let lastReviewedDate:  String    // "YYYY-MM-DD" — NEW in Epic 4
}
```

`SRSEngine.rate(_:rating:)` sets `lastReviewedDate` to today's date string (same format as `dueDate`). This keeps all post-rating field updates in one place.

---

## New In-Memory Type — `FocusSession`

**Not persisted.** Lives in `@State` on the sidebar tab container. Captures a snapshot of the queue at session start and is mutated as the user rates cards.

```swift
struct FocusSession {

    // MARK: - Immutable session context (set at start, never changed)
    let totalCards: Int          // N — used in header "Today's Review — N cards"

    // MARK: - Mutable session progress
    var cards:      [VocabularyEntry]  // Remaining unrated cards (including retry re-appends)
    var ratedCount: Int                // Cards successfully rated so far
    var tally:      RatingTally        // Per-rating count accumulator
    var failedCardIDs: Set<Int64>      // IDs of cards that have already failed once (retry limit)

    // MARK: - Computed
    var isComplete: Bool { cards.isEmpty }
    var current:    VocabularyEntry? { cards.first }

    // MARK: - Mutations
    mutating func advance()                              // Remove first card
    mutating func appendRetry(_ entry: VocabularyEntry) // Append failed card once
    mutating func recordRating(_ rating: SRSRating)     // Increment tally + ratedCount

    // MARK: - Nested tally
    struct RatingTally {
        var again: Int = 0
        var hard:  Int = 0
        var good:  Int = 0
        var easy:  Int = 0
    }
}
```

**Key invariants**:
- `totalCards` is set at init from the queue snapshot count. It never changes during the session (even if retry cards are appended — they were already in the original queue).
- `failedCardIDs` tracks which entries have already been re-appended once. An entry in this set is never re-appended again after a second failure.
- `ratedCount` increments only on a successful write — it does not increment when a write fails.

---

## New Repository Methods

These methods are added to `VocabularyEntryRepository`.

### `setDifficultyLabel(id: Int64, label: DifficultyLabel) throws`

Writes the user-selected difficulty to the entry. Issues a single UPDATE touching only `difficultyLabel`.

```sql
UPDATE vocabulary_entries
SET difficultyLabel = ?
WHERE id = ?
```

- Synchronous.
- Throws on DB error (callers use `Task { try? ... }` — silent failure is acceptable per Research Decision 4).
- Does not touch any SRS column or `triageStatus`.

### Extended `applyRating(id: Int64, update: SRSUpdate) throws`

The existing Epic 3 method is extended to also write `lastReviewedDate` in the same `UPDATE`:

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

- One statement, one transaction — atomic.
- `lastReviewedDate` value comes from `update.lastReviewedDate` (computed in `SRSEngine.rate`).

---

## Card State Machine (per card, within a session)

```
 [Session start — card loaded]
         │
         ▼
    hidden (isRevealed = false)
         │
         │ Space / Reveal button
         ▼
    revealed (isRevealed = true)
         │
    ┌────┴──────────────────┐
    │                       │
    │ Rating submitted       │ Rating write fails
    │ (write succeeds)       │
    ▼                       ▼
  advance to          inline error shown
  next card           → append to end of
  + tally++             queue (if first fail)
  + ratedCount++        → advance to next card
                        (ratedCount NOT incremented)
```

---

## Relative Date Formatting

`lastReviewedDate` and `dueDate` are both `YYYY-MM-DD` strings. The card view computes human-readable relative strings at render time using `Calendar.current`:

| Condition | "Last review" display | "Next review" display |
|-----------|----------------------|----------------------|
| `nil` | "Never" | "Today" |
| Same calendar day as today | "Today" | "Today" |
| 1 day ago / in 1 day | "Yesterday" | "Tomorrow" |
| N days ago / in N days | "N days ago" | "In N days" |

Relative date computation is a pure function (takes a date string + today string, returns a display string) — easily unit-tested with fixed inputs.
