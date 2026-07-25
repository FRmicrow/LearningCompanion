# Quickstart: SRS Engine — Spaced Repetition

**Feature**: 008-srs-engine  
**Date**: 2025-07-22

---

## Purpose

This guide provides runnable validation scenarios to verify that the SRS Engine works correctly after implementation. It is **not** a code guide — see [`contracts/srs-engine.md`](contracts/srs-engine.md) for interface contracts and [`data-model.md`](data-model.md) for entity definitions.

---

## Prerequisites

- macOS 13+
- `swift build` available
- App built and running (menu bar icon visible)
- Epic 2 (Inbox) implemented — `markSaved(id:)` must set SRS defaults
- At least a few English words captured and saved via the Inbox

---

## Build

```bash
swift build
```

Expected: zero errors, zero warnings related to this feature.

---

## Test

```bash
swift test
```

Expected: all tests pass, including:
- New tests for `SRSEngine` (algorithm unit tests)
- New tests for `VocabularyEntryRepository` SRS methods (`fetchDueEntries`, `applyRating`)
- Migration `v4` test (existing entries unaffected; new columns present with correct defaults)

Run a focused subset:

```bash
swift test --filter VocabularyEntryRepository
```

---

## Validation Scenarios

### Scenario 1 — Newly saved word enters the daily queue

1. Launch the app.
2. Copy an English word (e.g. "ephemeral") to the clipboard.
3. Open the sidebar → Inbox tab.
4. Tap **Save** on the word.

**Expected**:
- The word is removed from the Inbox.
- In the database (verifiable via test or direct DB inspection): the entry has `srsState = 'new'`, `dueDate = today`, `interval = 1.0`, `easeFactor = 2.5`, `ratingCount = 0`.
- The daily progress bar (Epic 1) increments its count by 1 (the word is now in the queue).

---

### Scenario 2 — Rating a word as Good

1. Have at least one saved word due today (saved in Scenario 1 or earlier).
2. Open the sidebar → Learn tab (Epic 4 required for UI; verify via test without UI).
3. Rate the word **Good**.

**Expected**:
- `ratingCount` increments to 1.
- `srsState` becomes `'learning'` (first rating, interval < 7).
- `interval` becomes `1.0 × 2.5 = 2.5`.
- `dueDate` is set to today + 3 days (round(2.5) = 3 — standard rounding, round-half-to-even may give 2; verify with the round function used in implementation).
- The word no longer appears in today's queue.
- The daily queue `ValueObservation` fires within 500 ms.

---

### Scenario 3 — Rating a word as Again resets the interval

1. Have a word with `interval > 1` (e.g., rated Good twice, now `interval ≈ 6.25`).
2. Rate it **Again**.

**Expected**:
- `interval` resets to `1.0`.
- `dueDate` is set to tomorrow.
- `easeFactor` decreases by 0.2 (minimum 1.3).
- `srsState` remains `'learning'` (ratingCount ≥ 1, interval < 7).
- The word re-appears in tomorrow's queue, not today's.

---

### Scenario 4 — State progresses New → Learning → Known → Mastered

Verifiable via unit test without UI. Simulate the following rating sequence programmatically:

| Rating | Expected new interval | Expected `srsState` |
|--------|----------------------|---------------------|
| Good (1st) | 2.5 | learning |
| Good (2nd) | 6.25 | learning |
| Good (3rd) | 15.625 | known |
| Good (4th) | 39.0625 | mastered |

**Expected**:
- After rating 3, `srsState == 'known'` (interval ≥ 7).
- After rating 4, `srsState == 'mastered'` (interval ≥ 21).
- All values survive an app restart (persisted to SQLite).

---

### Scenario 5 — Daily queue contains only due entries

1. Insert test entries with varying `dueDate` values:
   - Entry A: `dueDate = yesterday`
   - Entry B: `dueDate = today`
   - Entry C: `dueDate = tomorrow`
2. Query `fetchDueEntries()`.

**Expected**:
- Entry A and Entry B are returned (in that order — oldest first).
- Entry C is NOT returned.
- Verifiable via `swift test --filter VocabularyEntryRepository`.

---

### Scenario 6 — Overdue entries appear and are rated normally

1. Have a word with `dueDate` set 5 days in the past (simulating a missed review week).
2. Open the Learn tab — the word appears.
3. Rate it **Easy**.

**Expected**:
- The word's interval is computed from its stored `interval` value (not from the overdue gap).
- `dueDate` is set to today + round(newInterval).
- The word disappears from today's queue immediately.

---

### Scenario 7 — Rating write failure handling

*Requires a test that injects a DB write failure (e.g., pass a closed `DatabaseQueue`).*

1. Trigger `applyRating(id:update:)` against a database that will fail the write.

**Expected**:
- `applyRating` throws an error.
- The entry's SRS fields in the database are unchanged (the transaction was rolled back).
- The calling view (Epic 4) receives the error and re-queues the entry for the current session.
- No automatic retry is performed.

---

### Scenario 8 — Migration v4 is non-destructive

1. Start with a database at `v2` (pre-Epic 2 state) containing existing vocabulary entries.
2. Run `swift build && swift run` (or test setup) to trigger migrations `v3` and `v4`.

**Expected**:
- All existing entries are preserved with their original `englishText`, `frenchTranslation`, `translationStatus`, etc.
- Each existing entry now has: `srsState = 'new'`, `dueDate = today`, `interval = 1.0`, `easeFactor = 2.5`, `ratingCount = 0`.
- No existing columns are modified or removed.

---

### Performance Check — Rating write latency

1. Open the Learn tab with several due entries.
2. Rate a word and measure the time from button press to the daily queue updating.

**Expected**:
- The database write completes within 100 ms (SC-1, F-304).
- The daily queue `ValueObservation` reflects the update within 500 ms (SC-1 clarified).

---

## References

- Interface contracts: [`contracts/srs-engine.md`](contracts/srs-engine.md)
- Data model: [`data-model.md`](data-model.md)
- Feature spec: [`spec.md`](spec.md)
- Epic 2 reference (Inbox / `markSaved`): [`../007-inbox-capture-triage/quickstart.md`](../007-inbox-capture-triage/quickstart.md)
