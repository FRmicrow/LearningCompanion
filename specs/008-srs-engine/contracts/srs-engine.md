# Contract: SRS Engine

**Feature**: 008-srs-engine  
**Date**: 2025-07-22  
**Type**: Service contract + Repository extension + Data model extension

---

## Overview

This contract defines:

1. **`SRSState`** — the four-value enum representing a word's learning lifecycle.
2. **`SRSRating`** — the four-value enum representing the user's recall rating.
3. **`SRSUpdate`** — the value type carrying algorithm output.
4. **`SRSEngine`** — the pure scheduling service.
5. **New `VocabularyEntryRepository` methods** — `fetchDueEntries()`, `fetchDueCount()`, `applyRating(id:update:)`.
6. **Modified `VocabularyEntryRepository.markSaved(id:)`** — extended to set SRS defaults atomically.
7. **`VocabularyEntry` extension** — five new optional fields and `CodingKeys` additions.
8. **Migration `v4`** — five new nullable columns on `vocabulary_entries`.

---

## `SRSState`

```swift
enum SRSState: String, Codable {
    case new       = "new"
    case learning  = "learning"
    case known     = "known"
    case mastered  = "mastered"
}
```

| # | Contract |
|---|----------|
| C-01 | `SRSState` is a top-level type (not nested in `VocabularyEntry`). |
| C-02 | Raw values match the SQL column values in migration `v4`. |
| C-03 | `SRSState` is `Codable` to support GRDB persistence. |
| C-04 | `new` represents an entry with zero ratings ever submitted (`ratingCount == 0`). |
| C-05 | `learning` represents an entry with ≥ 1 rating and `interval < 7.0`. |
| C-06 | `known` represents an entry with `interval ≥ 7.0`. |
| C-07 | `mastered` represents an entry with `interval ≥ 21.0`. |

---

## `SRSRating`

```swift
enum SRSRating {
    case again
    case hard
    case good
    case easy
}
```

| # | Contract |
|---|----------|
| C-08 | `SRSRating` is a top-level type. It is not `Codable` — it is never persisted directly. |
| C-09 | `SRSRating` is the sole input type accepted by `SRSEngine.rate(_:rating:)`. |

---

## `SRSUpdate`

```swift
struct SRSUpdate {
    let srsState:    SRSState
    let dueDate:     String    // "YYYY-MM-DD" in local calendar
    let interval:    Double
    let easeFactor:  Double
    let ratingCount: Int
}
```

| # | Contract |
|---|----------|
| C-10 | `SRSUpdate` is a value type (struct). |
| C-11 | `dueDate` is always a `YYYY-MM-DD` string in the device's local calendar. |
| C-12 | `interval` is always ≥ 1.0. |
| C-13 | `easeFactor` is always ≥ 1.3. |
| C-14 | `ratingCount` equals the prior `ratingCount + 1`. |

---

## `SRSEngine`

```swift
struct SRSEngine {
    static func rate(_ entry: VocabularyEntry, rating: SRSRating) -> SRSUpdate
}
```

| # | Contract |
|---|----------|
| C-15 | `SRSEngine.rate(_:rating:)` is a static pure function. It performs no I/O and has no side effects. |
| C-16 | The function reads only `entry.interval ?? 1.0`, `entry.easeFactor ?? 2.5`, and `entry.ratingCount ?? 0`. It does not inspect `englishText`, `frenchTranslation`, or any other field. |
| C-17 | On `again`: new `interval = 1.0`; new `easeFactor = max(1.3, (entry.easeFactor ?? 2.5) - 0.2)`. |
| C-18 | On `hard`: new `interval = max(1.0, (entry.interval ?? 1.0) * 1.2)`; new `easeFactor = max(1.3, (entry.easeFactor ?? 2.5) - 0.15)`. |
| C-19 | On `good`: new `interval = max(1.0, (entry.interval ?? 1.0) * (entry.easeFactor ?? 2.5))`; `easeFactor` unchanged. |
| C-20 | On `easy`: new `interval = max(1.0, (entry.interval ?? 1.0) * (entry.easeFactor ?? 2.5) * 1.3)`; `easeFactor` unchanged. |
| C-21 | `dueDate` is computed as `Calendar.current` date `+ round(newInterval)` days, formatted as `YYYY-MM-DD`. |
| C-22 | `srsState` is derived from new `ratingCount` and new `interval`: `ratingCount == 0` → `.new`; `interval < 7` → `.learning`; `interval < 21` → `.known`; else → `.mastered`. |
| C-23 | The function is deterministic: the same input always produces the same output. |
| C-24 | The function does **not** throw. All inputs have safe defaults (nil-coalesced to initial values). |

---

## `VocabularyEntry` Extension

```swift
extension VocabularyEntry {
    var srsState:    SRSState? // stored field
    var dueDate:     String?   // stored field, "YYYY-MM-DD"
    var interval:    Double?   // stored field
    var easeFactor:  Double?   // stored field
    var ratingCount: Int?      // stored field
}
```

| # | Contract |
|---|----------|
| C-25 | All five new fields are optional (nullable DB columns). |
| C-26 | `VocabularyEntry.CodingKeys` is extended with five new cases: `srsState = "srsState"`, `dueDate = "dueDate"`, `interval = "interval"`, `easeFactor = "easeFactor"`, `ratingCount = "ratingCount"`. |
| C-27 | Migration `v4` adds all five columns with nullable defaults (no `NOT NULL` constraint). |
| C-28 | Existing rows (inserted before `v4`) receive `srsState = 'new'`, `dueDate = date('now','localtime')`, `interval = 1.0`, `easeFactor = 2.5`, `ratingCount = 0` via the SQL DEFAULT. |
| C-29 | `SRSState` is decoded from the `srsState` column. A nil value is treated as `.new` by consumers. |

---

## `VocabularyEntryRepository` — New Methods

```swift
/// Returns all entries with triageStatus == 'saved' AND dueDate <= today, ordered by dueDate ascending.
func fetchDueEntries() throws -> [VocabularyEntry]

/// Returns the count of entries in the daily review queue.
func fetchDueCount() throws -> Int

/// Applies the given SRSUpdate to the entry with the given id in a single atomic transaction.
/// Throws on DB error. Does NOT fall back silently.
func applyRating(id: Int64, update: SRSUpdate) throws
```

| # | Contract |
|---|----------|
| C-30 | `fetchDueEntries()` filters `Column("triageStatus") == "saved"` AND `Column("dueDate") <= todayString`, ordered by `Column("dueDate").asc`. |
| C-31 | `todayString` in all queries is computed at call time using `Calendar.current` in the device's local timezone, formatted as `YYYY-MM-DD`. |
| C-32 | `fetchDueCount()` uses GRDB `fetchCount(db)` on the same predicate as `fetchDueEntries()`. |
| C-33 | `applyRating(id:update:)` writes `srsState`, `dueDate`, `interval`, `easeFactor`, and `ratingCount` in a single `dbQueue.write { db in ... }` transaction. |
| C-34 | `applyRating(id:update:)` is `throws`. Callers catch the error and apply the write-failure behaviour (re-queue entry, surface error indicator). |
| C-35 | `applyRating(id:update:)` does **not** touch `triageStatus`, `englishText`, `frenchTranslation`, or any other column. |
| C-36 | All three new methods are synchronous. Callers dispatch them from a `Task` on the appropriate actor. |
| C-37 | GRDB `ValueObservation` fires automatically after `applyRating` writes — no explicit notification is needed. |

### Verification against implementation (T021)

The implementation in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift` was verified against C-30 through C-37:

- **C-30 ✅** `fetchDueEntries()` filters `Column("triageStatus") == "saved"` AND `Column("dueDate") <= today`, `.order(Column("dueDate").asc)`.
- **C-31 ✅** `todayString()` is a private helper computing `Calendar.current` at call time, formatted `yyyy-MM-dd`.
- **C-32 ✅** `fetchDueCount()` uses `.fetchCount(db)` on the same two-predicate filter.
- **C-33 ✅** `applyRating` executes one `dbQueue.write { db in try db.execute(sql: ...) }` updating all five fields.
- **C-34 ✅** `applyRating` is declared `throws`; no `try?` at call sites.
- **C-35 ✅** The UPDATE in `applyRating` sets only `srsState`, `dueDate`, `interval`, `easeFactor`, `ratingCount`.
- **C-36 ✅** All three methods are synchronous (no `async`).
- **C-37 ✅** `ValueObservation` fires automatically on the GRDB write — confirmed by `DailyQueueObservationTests`.

No discrepancies found. Contract is accurate as written.

---

## ValueObservation Patterns (T021, T022)

These patterns are for use in Epic 4 (Learn/Review views) and Epic 1 (DailyProgressBar).
Both follow the established project pattern from `VocabularyListView`.

### Daily Queue Entries Observation

```swift
// In a @MainActor SwiftUI view or view model:
let observation = ValueObservation.tracking { db in
    let today = /* todayString() */ {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = Calendar.current
        return fmt.string(from: Date())
    }()
    return try VocabularyEntry
        .filter(Column("triageStatus") == "saved")
        .filter(Column("dueDate") <= today)
        .order(Column("dueDate").asc)
        .fetchAll(db)
}

observationTask = Task { @MainActor in
    do {
        for try await entries in observation.values(in: repository.dbQueue) {
            self.dueEntries = entries
        }
    } catch {
        // DB closed or app shutting down — ignore
    }
}
```

Cancel via `observationTask?.cancel()` in `.onDisappear`.

### Daily Queue Count Observation (for DailyProgressBar)

```swift
let countObservation = ValueObservation.tracking { db in
    let today = /* todayString() */ {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = Calendar.current
        return fmt.string(from: Date())
    }()
    return try VocabularyEntry
        .filter(Column("triageStatus") == "saved")
        .filter(Column("dueDate") <= today)
        .fetchCount(db)
}

countTask = Task { @MainActor in
    do {
        for try await count in countObservation.values(in: repository.dbQueue) {
            self.dueCount = count
        }
    } catch { }
}
```

Both observations fire automatically after every `applyRating` write (C-37). No `NotificationCenter` or manual refresh is needed.

---

## Modified `markSaved(id:)` (Epic 2 method, extended here)

| # | Contract |
|---|----------|
| C-38 | `markSaved(id:)` is updated to set `triageStatus = 'saved'`, `srsState = 'new'`, `dueDate = todayString`, `interval = 1.0`, `easeFactor = 2.5`, `ratingCount = 0` in a **single UPDATE statement**. |
| C-39 | The SRS defaults and `triageStatus` transition are atomic — there is no observable state where `triageStatus == 'saved'` but SRS fields are null. |
| C-40 | `todayString` is computed at call time (same pattern as C-31). |

---

## Threading Contracts

| # | Contract |
|---|----------|
| C-41 | `SRSEngine.rate(_:rating:)` may be called from any thread. It is stateless and thread-safe. |
| C-42 | `applyRating(id:update:)` is called from the Learn/Review view (Epic 4) inside a `Task { try repository.applyRating(...) }`. On error, the task surfaces the failure to the calling view. |
| C-43 | `fetchDueEntries()` and `fetchDueCount()` are driven via `ValueObservation`, whose tasks run `@MainActor`, following the established project pattern. |
| C-44 | `applyRating` writes complete within 100 ms as perceived by the caller (F-304). GRDB's synchronous write path on a local SQLite database satisfies this constraint in practice. |
| C-45 | The daily queue `ValueObservation` reflects a successful `applyRating` write within 500 ms (SC-1, Clarification Q4). GRDB `ValueObservation` fires on the next runloop cycle after the write transaction commits. |
