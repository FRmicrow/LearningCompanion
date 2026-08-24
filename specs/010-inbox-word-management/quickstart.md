# Quickstart: Inbox Word Management & Learn Session Control

**Feature**: 010-inbox-word-management  
**Date**: 2025-07-25

---

## Prerequisites

- Swift Package Manager project builds cleanly: `swift build`
- All tests pass before this feature: `swift test`
- Migration v5 is in place (Epic 4 columns exist in the schema)

---

## Build

```bash
swift build
```

Expected: zero errors, zero warnings added by this feature.

---

## Run Tests

```bash
# Full suite
swift test

# This feature's new test suites only
swift test --filter DatabaseMigrationV6Tests
swift test --filter InboxSelectionTests
swift test --filter LearnSessionRestartTests
swift test --filter MasteryTests

# Regression — existing suites must still pass
swift test --filter VocabularyEntryRepository
swift test --filter CaptureToStorage
```

All tests must pass with zero failures.

---

## Scenario 1: Migration v6 — `isMastered` column exists

**Purpose**: Verify the new column is created by migration `v6`.

**Test suite**: `DatabaseMigrationV6Tests`

**Steps**:
1. Create an in-memory database: `Database(path: ":memory:")`
2. Assert that the `vocabulary_entries` table has a column named `isMastered`
3. Insert a new `VocabularyEntry` via `upsert(englishText:)`
4. Fetch the entry and assert `isMastered == false`

**Expected**: Column exists, defaults to `false` for newly inserted entries.

---

## Scenario 2: `fetchDueEntries` excludes mastered words

**Purpose**: Verify mastered words never appear in the daily SRS queue.

**Test suite**: `MasteryTests`

**Steps**:
1. Create a repo with an in-memory DB
2. Save an entry via `markSaved(id:)` with `dueDate = today`
3. Assert `fetchDueEntries()` returns the entry
4. Call `markMastered(id:)`
5. Assert `fetchDueEntries()` no longer contains that entry

**Expected**: Entry is excluded from the daily queue after mastery.

---

## Scenario 3: `fetchLearnPool` excludes mastered words, includes all saved

**Purpose**: Verify the Restart session pool includes non-mastered saved entries regardless of `dueDate`.

**Test suite**: `MasteryTests`

**Steps**:
1. Save three entries: one due today, one due in 7 days, one mastered
2. Call `fetchLearnPool()`
3. Assert the result contains the two non-mastered entries
4. Assert the result does NOT contain the mastered entry

**Expected**: Pool = all saved + non-mastered entries, regardless of due date.

---

## Scenario 4: `deleteAll` removes exactly the selected entries

**Purpose**: Verify batch delete is atomic and correct.

**Test suite**: `InboxSelectionTests`

**Steps**:
1. Insert 5 entries via `upsert`
2. Collect the IDs of 3 of them
3. Call `repository.deleteAll(ids: [id1, id2, id3])`
4. Call `repository.fetchAll()`
5. Assert the result contains exactly the 2 non-deleted entries

**Expected**: Exactly the 3 selected entries are deleted; the other 2 remain.

---

## Scenario 5: `deleteAll` with empty array is a no-op

**Purpose**: Verify no crash and no change when `ids` is empty.

**Test suite**: `InboxSelectionTests`

**Steps**:
1. Insert 2 entries
2. Call `repository.deleteAll(ids: [])`
3. Assert `repository.fetchAll()` still returns 2 entries

**Expected**: No entries deleted; no error thrown.

---

## Scenario 6: Restart sampling — pool ≤ 20

**Purpose**: Verify all entries are included when pool size is within the threshold.

**Test suite**: `LearnSessionRestartTests`

**Steps**:
1. Save 15 non-mastered entries
2. Fetch the learn pool
3. Assert pool count == 15
4. Apply the sampling rule (pool.count ≤ 20 → use all)
5. Assert session cards count == 15

**Expected**: All 15 entries are included; no random sampling occurs.

---

## Scenario 7: Restart sampling — pool > 20

**Purpose**: Verify exactly 20 entries are sampled when the pool exceeds the threshold.

**Test suite**: `LearnSessionRestartTests`

**Steps**:
1. Save 30 non-mastered entries
2. Fetch the learn pool (30 entries)
3. Apply the sampling rule (pool.count > 20 → `pool.shuffled().prefix(20)`)
4. Assert session cards count == 20
5. Assert all 20 sampled entries have IDs within the original 30

**Expected**: Exactly 20 entries, all drawn from the original pool.

---

## Scenario 8: Easy rating sets `isMastered = true` and word exits queue

**Purpose**: End-to-end verification that an Easy rating in Learn mode permanently retires the word.

**Test suite**: `MasteryTests`

**Steps**:
1. Save an entry; assert it appears in `fetchDueEntries()`
2. Simulate an Easy rating: call `applyRating(id:update:)` with the SRS result, then call `markMastered(id:)`
3. Assert `repository.fetchDueEntries()` no longer contains the entry
4. Assert `repository.fetchLearnPool()` no longer contains the entry
5. Assert `repository.fetchAll()` still contains the entry (visible but mastered)

**Expected**: Entry is mastered, excluded from queues, but still in the database.

---

## Scenario 9: Mastered word is visible in vocabulary list

**Purpose**: Verify mastered words are not deleted — they remain visible.

**Test suite**: `MasteryTests`

**Steps**:
1. Save an entry, call `markMastered(id:)`
2. Call `repository.fetchAll()`
3. Assert the mastered entry is present with `isMastered == true`

**Expected**: Entry is present in `fetchAll()` results with mastery flag set.

---

## Manual Smoke Test (UI verification)

After building the app:

1. **Inbox selection mode**: Open the sidebar → Inbox tab → tap Select → verify checkboxes appear on each word row and a Cancel button is shown.
2. **Bulk delete**: Select 2–3 words → tap Delete Selected → verify they disappear immediately from the list (ValueObservation update).
3. **Add to Learn**: Select 2 words → tap Add to Learn → verify the app switches to the Learn tab and the session shows only those 2 cards.
4. **Restart with pool ≤ 20**: Complete a Learn session with < 20 words → tap Restart Session → verify a new session starts with all available non-mastered words.
5. **Restart with pool > 20**: Ensure > 20 saved non-mastered words exist → tap Restart Session → verify session shows exactly 20 cards.
6. **Easy rating = mastered**: In a Learn session, rate a word Easy → verify the word shows a "Mastered" indicator in the vocabulary list → open a new session and verify the word is not in the queue.
7. **Mastered word excluded from daily queue**: After mastering a word, verify the daily progress counter (DailyProgressBar) decreases by 1.

---

## Performance Validation

Per Constitution Constraints:

| Constraint | Threshold | How to Verify |
|-----------|-----------|---------------|
| Capture-to-DB-insert latency | ≤ 3,000 ms | `swift test --filter CaptureToStorage` — must still pass |
| Background CPU at idle | < 1% | Activity Monitor after launch with 50+ entries |
| Background RAM | < 50 MB | Activity Monitor — selection state (a `Set<Int64>`) adds negligible memory |

---

## References

- Data model: [`data-model.md`](data-model.md)
- Contracts: [`contracts/inbox-word-management.md`](contracts/inbox-word-management.md)
- Spec: [`spec.md`](spec.md)
- Epic 4 contract (FocusSession): [`specs/009-learn-review-sessions/contracts/learn-review-sessions.md`](../009-learn-review-sessions/contracts/learn-review-sessions.md)
