# Data Model: SRS Engine — Spaced Repetition

**Feature**: 008-srs-engine  
**Date**: 2025-07-22

---

## Overview

This epic introduces one DB migration (`v4`) that adds five new columns to the existing `vocabulary_entries` table. No new tables are created. Two new Swift enum types are introduced (`SRSState`, `SRSRating`). One new value type (`SRSUpdate`) carries algorithm output. One new service type (`SRSEngine`) encapsulates the pure scheduling function.

---

## Schema Change — Migration v4

### `vocabulary_entries` — added columns

| Column | SQL Type | Nullable | Default |
|--------|----------|----------|---------|
| `srsState` | `TEXT` | YES (nullable for migration safety) | `'new'` |
| `dueDate` | `TEXT` | YES | today's date (`YYYY-MM-DD`) |
| `interval` | `REAL` | YES | `1.0` |
| `easeFactor` | `REAL` | YES | `2.5` |
| `ratingCount` | `INTEGER` | YES | `0` |

> **Why nullable?** The migration assumptions state that columns are added without `NOT NULL` to keep the migration non-breaking for any in-flight app state. Swift optionals handle the nil cases.

**SQL** (GRDB `alter` DSL equivalent):
```sql
ALTER TABLE vocabulary_entries ADD COLUMN srsState     TEXT    DEFAULT 'new'
ALTER TABLE vocabulary_entries ADD COLUMN dueDate      TEXT    DEFAULT (date('now','localtime'))
ALTER TABLE vocabulary_entries ADD COLUMN interval     REAL    DEFAULT 1.0
ALTER TABLE vocabulary_entries ADD COLUMN easeFactor   REAL    DEFAULT 2.5
ALTER TABLE vocabulary_entries ADD COLUMN ratingCount  INTEGER DEFAULT 0
```

**Index** — accelerates the daily queue query:
```sql
CREATE INDEX idx_vocabulary_due_date ON vocabulary_entries (dueDate)
```

**Migration registration**: Registered as `"v4"` in `Database.migrate()`. Runs after `"v3"` (Epic 2's `triageStatus` column).

---

## Updated Entity — `VocabularyEntry`

`VocabularyEntry` gains five new stored fields and one new nested enum.

### New fields

| Field | Swift Type | DB Column | Default |
|-------|-----------|-----------|---------|
| `srsState` | `SRSState?` | `srsState` | `.new` (nil treated as `.new`) |
| `dueDate` | `String?` | `dueDate` | today's date string |
| `interval` | `Double?` | `interval` | `1.0` |
| `easeFactor` | `Double?` | `easeFactor` | `2.5` |
| `ratingCount` | `Int?` | `ratingCount` | `0` |

All new fields are `Optional` to match the nullable SQL columns. Consumers unwrap with a project-standard default (e.g., `entry.srsState ?? .new`).

### Full `VocabularyEntry` field summary (after migration v4)

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
| `srsState` | `SRSState?` | **NEW** — lifecycle state |
| `dueDate` | `String?` | **NEW** — next review date (`YYYY-MM-DD`) |
| `interval` | `Double?` | **NEW** — current review interval in days (float) |
| `easeFactor` | `Double?` | **NEW** — SM-2 ease multiplier |
| `ratingCount` | `Int?` | **NEW** — number of ratings ever submitted |

**`CodingKeys` additions** (camelCase → camelCase per project convention):
- `srsState` → `"srsState"`
- `dueDate` → `"dueDate"`
- `interval` → `"interval"`
- `easeFactor` → `"easeFactor"`
- `ratingCount` → `"ratingCount"`

---

## New Enum — `SRSState`

Top-level (not nested in `VocabularyEntry`, to be shared with `SRSEngine`).

```swift
enum SRSState: String, Codable {
    case new       = "new"       // Never rated (ratingCount == 0)
    case learning  = "learning"  // Rated ≥ 1 time, interval < 7
    case known     = "known"     // interval ≥ 7
    case mastered  = "mastered"  // interval ≥ 21
}
```

**State derivation rule** (applied after every rating by `SRSEngine`):

```
if ratingCount == 0         → .new
else if interval < 7        → .learning
else if interval < 21       → .known
else                        → .mastered
```

---

## New Enum — `SRSRating`

Top-level, used as the input to `SRSEngine.rate(_:rating:)`.

```swift
enum SRSRating {
    case again  // Interval resets to 1; easeFactor -= 0.2 (min 1.3)
    case hard   // Interval × 1.2; easeFactor -= 0.15
    case good   // Interval × easeFactor
    case easy   // Interval × easeFactor × 1.3
}
```

---

## New Value Type — `SRSUpdate`

Carries the output of `SRSEngine.rate(_:rating:)`. Not persisted directly — the repository applies it to the DB entry.

```swift
struct SRSUpdate {
    let srsState:    SRSState
    let dueDate:     String    // "YYYY-MM-DD"
    let interval:    Double
    let easeFactor:  Double
    let ratingCount: Int
}
```

---

## New Service Type — `SRSEngine`

A stateless struct. Contains the SM-2 logic as a pure function.

```swift
struct SRSEngine {
    /// Applies the SM-2 algorithm to the given entry and rating.
    /// Returns the updated SRS fields as an `SRSUpdate` value.
    /// Does not perform I/O. Does not mutate the entry.
    static func rate(_ entry: VocabularyEntry, rating: SRSRating) -> SRSUpdate
}
```

**Algorithm** (from F-302):

| Rating | `interval` update | `easeFactor` update |
|--------|------------------|--------------------|
| `again` | reset to `1.0` | `max(1.3, easeFactor - 0.2)` |
| `hard` | `max(1.0, interval × 1.2)` | `max(1.3, easeFactor - 0.15)` |
| `good` | `max(1.0, interval × easeFactor)` | unchanged |
| `easy` | `max(1.0, interval × easeFactor × 1.3)` | unchanged |

`dueDate` = `today + round(newInterval)` calendar days (local calendar).

`srsState` derived from new `ratingCount` and new `interval` per the derivation rule above.

---

## New Repository Methods

These methods are added to `VocabularyEntryRepository`.

### `fetchDueEntries() throws -> [VocabularyEntry]`

Returns all entries where `dueDate ≤ today` AND `triageStatus == 'saved'`, ordered by `dueDate` ascending (oldest/most-overdue first).

```sql
SELECT * FROM vocabulary_entries
WHERE triageStatus = 'saved'
  AND dueDate <= date('now','localtime')
ORDER BY dueDate ASC
```

### `fetchDueCount() throws -> Int`

Returns the count of entries in the daily queue. Used by the daily progress bar (`ValueObservation`).

```sql
SELECT COUNT(*) FROM vocabulary_entries
WHERE triageStatus = 'saved'
  AND dueDate <= date('now','localtime')
```

### `applyRating(id:update:) throws`

Applies an `SRSUpdate` to the given entry in a single atomic transaction.

```sql
UPDATE vocabulary_entries
SET srsState    = ?,
    dueDate     = ?,
    interval    = ?,
    easeFactor  = ?,
    ratingCount = ?
WHERE id = ?
```

### Updated `markSaved(id:)` (from Epic 2)

The existing `markSaved(id:)` from Epic 2 must be extended to also set the SRS default fields atomically:

```sql
UPDATE vocabulary_entries
SET triageStatus = 'saved',
    srsState     = 'new',
    dueDate      = date('now','localtime'),
    interval     = 1.0,
    easeFactor   = 2.5,
    ratingCount  = 0
WHERE id = ?
```

> **Note**: This is the only safe place to initialise SRS fields — see Research Decision 4.

---

## State Transitions — `srsState`

```
 [Inbox Save]
      │
      ▼
     new  (ratingCount = 0)
      │
      │ first rating (any)
      ▼
  learning  (ratingCount ≥ 1, interval < 7)
      │
      │ positive ratings accumulate interval ≥ 7
      ▼
    known  (interval ≥ 7)
      │
      │ interval grows to ≥ 21
      ▼
  mastered  (interval ≥ 21)
      │
      ◄──── Again (from any non-new state) ── interval resets to 1.0 → learning
```

- `Again` from `learning`, `known`, or `mastered` always returns to `learning` (ratingCount ≥ 1, interval < 7).
- There is no transition from `learning`/`known`/`mastered` back to `new` — `new` strictly means "never rated".

---

## Daily Queue `ValueObservation`

```swift
ValueObservation.tracking { db in
    try VocabularyEntry
        .filter(Column("triageStatus") == "saved")
        .filter(Column("dueDate") <= todayString)
        .order(Column("dueDate").asc)
        .fetchAll(db)
}
```

Where `todayString` is `DateFormatter` output for `yyyy-MM-dd` in the device's local calendar, computed at observation time.

Driven from the Learn/Review views (Epic 4) and the daily progress bar (Epic 1), following the existing `Task { @MainActor in ... }` pattern.

---

## Queue Count `ValueObservation`

```swift
ValueObservation.tracking { db in
    try VocabularyEntry
        .filter(Column("triageStatus") == "saved")
        .filter(Column("dueDate") <= todayString)
        .fetchCount(db)
}
```

Exposes a single `Int` to `DailyProgressBar` and the session header in Epic 4.
