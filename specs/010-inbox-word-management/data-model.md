# Data Model: Inbox Word Management & Learn Session Control

**Feature**: 010-inbox-word-management  
**Date**: 2025-07-25

---

## Database Migration v6

A single additive migration adds one new boolean column to `vocabulary_entries`.

### New Column: `isMastered`

| Property | Value |
|----------|-------|
| Table | `vocabulary_entries` |
| Column | `isMastered` |
| SQL type | `INTEGER` (SQLite boolean) |
| Default | `0` (`false`) |
| Nullable | No (NOT NULL with default) |
| Constraint | None beyond NOT NULL |

**Migration SQL** (registered as `"v6"` in `Database.migrate()`):

```sql
ALTER TABLE vocabulary_entries
ADD COLUMN isMastered INTEGER NOT NULL DEFAULT 0
```

**Index**: An index on `isMastered` is not required — mastery exclusion is always combined with the `triageStatus = 'saved'` filter which already has an index (`idx_vocabulary_triage_status`). SQLite will use the existing index efficiently.

**Existing rows**: All entries have `isMastered = 0` after migration. No data is lost or changed beyond adding the default value.

---

## Updated `VocabularyEntry` Model

`isMastered: Bool` is added to the `VocabularyEntry` struct.

```swift
struct VocabularyEntry: Codable, FetchableRecord, MutablePersistableRecord {
    // ... existing fields ...

    // MARK: - Mastery field (migration v6)

    var isMastered: Bool  // default false; set to true on Easy rating in Learn mode
}
```

**`CodingKeys` addition**:

```swift
case isMastered = "isMastered"
```

---

## `VocabularyEntry` State Machine (updated)

The entry lifecycle gains a `isMastered` flag layered on top of the existing `triageStatus` and `srsState` fields:

```
triageStatus = unreviewed  →  (Save)  →  triageStatus = saved, srsState = new
                                          isMastered = false (default)
                                               ↓
                                    (Learn session: Easy rating)
                                               ↓
                                         isMastered = true
                                    (excluded from all future queues)
```

Key invariants:
- `isMastered` can only transition `false → true` in this iteration. There is no UI path to reverse mastery.
- `isMastered = true` does not change `triageStatus`. The entry remains `triageStatus = 'saved'` and is still visible in vocabulary views.
- `isMastered = true` does not stop SRS field updates if the entry is explicitly added to an on-demand session and rated again — but this scenario is edge-only and the mastery flag is not re-cleared.

---

## New Repository Queries

### `fetchLearnPool() -> [VocabularyEntry]`

Returns all entries eligible for a Restart Learn session: saved, not mastered.

```
SELECT * FROM vocabulary_entries
WHERE triageStatus = 'saved'
  AND isMastered   = 0
ORDER BY dueDate ASC
```

Used by:
- `LearnView.startSession(restartMode: true)` to build the Restart session queue.
- The `ValueObservation` in `LearnView` for the idle state word count (replacing the `fetchDueEntries` observation when needed).

### `markMastered(id: Int64) throws`

Targeted single-column UPDATE, called after a successful `.easy` rating write.

```
UPDATE vocabulary_entries
SET isMastered = 1
WHERE id = ?
```

### `deleteAll(ids: [Int64]) throws`

Batch delete for the Inbox multi-select "Delete Selected" action.

```
DELETE FROM vocabulary_entries
WHERE id IN (?, ?, ...)
```

Implemented via GRDB's `VocabularyEntry.filter(ids: ...).deleteAll(db)` inside a single `dbQueue.write` transaction.

---

## In-Memory State: Selection Mode

Selection mode is purely transient UI state — it is never persisted to the database.

| Field | Type | Scope | Description |
|-------|------|-------|-------------|
| `isSelecting` | `Bool` | `@State` on Inbox view | Whether the Inbox is in multi-select mode |
| `selectedIDs` | `Set<Int64>` | `@State` on Inbox view | IDs of currently selected entries |

**Lifecycle**: Both fields are reset to `false` / empty set when the user taps Cancel, completes a Delete, or navigates away from the Inbox tab.

---

## In-Memory State: `FocusSession` (extended)

One new field is added to the existing `FocusSession` struct:

| Field | Type | Description |
|-------|------|-------------|
| `isOnDemand` | `Bool` | `true` when the session was constructed from an Inbox promotion rather than the SRS daily queue. Controls the Restart pool source. |

No other fields change. The `totalCards`, `cards`, `ratedCount`, `tally`, and `failedCardIDs` fields remain as-is.

---

## Summary of All Affected Files

| File | Change |
|------|--------|
| `ClipboardVocab/Persistence/Database.swift` | Register migration `v6` adding `isMastered` column |
| `ClipboardVocab/Models/VocabularyEntry.swift` | Add `isMastered: Bool` field and `CodingKeys` case |
| `ClipboardVocab/Persistence/VocabularyEntryRepository.swift` | Add `fetchLearnPool()`, `markMastered(id:)`, `deleteAll(ids:)` |
| `ClipboardVocab/Models/FocusSession.swift` | Add `isOnDemand: Bool` field |
| `ClipboardVocab/UI/LearnView.swift` | Add Restart action, mastery write on Easy, on-demand session start |
| `ClipboardVocab/UI/SessionCompletionView.swift` | Add "Restart Session" button |
| `ClipboardVocab/UI/VocabularyListView.swift` | Add selection mode, Delete Selected, Add to Learn actions |
| `ClipboardVocab/UI/VocabularySidebarView.swift` | Thread on-demand session init from Inbox to LearnView |
| `Tests/Unit/VocabularyEntryRepositoryTests.swift` | Tests for `fetchLearnPool`, `markMastered`, `deleteAll` |
| `Tests/Unit/DatabaseMigrationV6Tests.swift` | Migration smoke-test for `isMastered` column |
| `Tests/Unit/InboxSelectionTests.swift` | Selection state transitions (new file) |
| `Tests/Unit/LearnSessionRestartTests.swift` | Restart pool sizing and random sampling (new file) |
| `Tests/Unit/MasteryTests.swift` | Easy-rating-sets-mastery and queue exclusion (new file) |
