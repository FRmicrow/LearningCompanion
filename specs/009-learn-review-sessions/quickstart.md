# Quickstart: Learn & Review — Sessions de révision

**Feature**: 009-learn-review-sessions  
**Date**: 2025-07-23

---

## Purpose

This guide provides runnable validation scenarios to verify that the Learn & Review sessions work correctly after implementation. It is **not** a code guide — see [`contracts/learn-review-sessions.md`](contracts/learn-review-sessions.md) for interface contracts and [`data-model.md`](data-model.md) for entity definitions.

---

## Prerequisites

- macOS 13+
- `swift build` available
- Epic 1 (Vocabulary Sidebar) implemented — the multi-view tab container must exist
- Epic 3 (SRS Engine) fully implemented — `fetchDueEntries()`, `applyRating(id:update:)`, and migration `v4` must be in place
- At least a few English words captured, saved via the Inbox, and present in the daily review queue (`dueDate ≤ today`, `triageStatus = 'saved'`)

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
- New tests for `FocusSession` logic (advance, appendRetry, recordRating, single-retry guard)
- New tests for relative date formatting (nil, today, yesterday, N days ago, tomorrow, in N days)
- New tests for `VocabularyEntryRepository.setDifficultyLabel`
- Extended tests for `applyRating` verifying `lastReviewedDate` is written atomically
- Migration `v5` test (existing entries unaffected; new columns present as `NULL`)

Run focused subsets:

```bash
swift test --filter VocabularyEntryRepository
swift test --filter LearnReview
```

---

## Validation Scenarios

### Scenario 1 — Open Learn tab with due cards

**Prerequisites**: At least 1 entry with `dueDate ≤ today` and `triageStatus = 'saved'`.

1. Launch the app.
2. Open the sidebar → Learn tab.

**Expected**:
- The first due card is displayed showing the English word prominently.
- The French translation is hidden (not visible).
- A "Reveal" button is present.
- The session header shows "Today's Review — N cards" and the counter shows "0 / N".
- Rating buttons (Again / Hard / Good / Easy) are **not** visible.

---

### Scenario 2 — Reveal and rate a Learn card

1. Open the Learn tab with at least one due card.
2. Press **Space** (or click Reveal).

**Expected (after Reveal)**:
- The French translation is now visible.
- Four rating buttons appear: Again, Hard, Good, Easy.
- The difficulty selector and metadata footer are visible.

3. Press **3** on the keyboard (= Good rating).

**Expected (after rating)**:
- The card is dismissed.
- The next due card appears (or the completion screen if this was the last card).
- The progress counter increments to "1 / N".
- In the database: the entry's `ratingCount` has incremented by 1, `dueDate` has been updated, and `lastReviewedDate` is set to today.

Verifiable via test without UI:
```bash
swift test --filter VocabularyEntryRepository
```

---

### Scenario 3 — Rating buttons blocked before Reveal

1. Open the Learn tab with a due card (translation hidden).
2. Press **1** on the keyboard (shortcut for "Again").

**Expected**:
- Nothing happens. No write is triggered.
- The card remains in its hidden state.
- The entry's SRS fields in the database are unchanged.

---

### Scenario 4 — Review mode (French → English)

1. Open the sidebar → Review tab.

**Expected**:
- The first due card shows the **French translation** prominently.
- The English word is hidden.
- A "Reveal" button is present.

2. Press Space to reveal.

**Expected**:
- The English word is now visible.
- Three rating buttons appear: Easy, Medium, Hard.

3. Tap **Medium**.

**Expected**:
- The card is dismissed and the next card loads.
- In the database: the SRS rating applied is **Good** (Medium maps to `.good`).
- `lastReviewedDate` is set to today.

---

### Scenario 5 — Difficulty indicator persists across sessions

1. Open a card in Learn or Review mode.
2. Tap **Hard** on the difficulty selector (radio button).

**Expected (immediately)**:
- The selector shows "Hard" as selected.
- In the database: `difficultyLabel = 'hard'` for that entry.

3. Rate the card and advance to the next.
4. Close the sidebar and reopen it.
5. Trigger a new session — the same word eventually appears.

**Expected (on re-appearance)**:
- The difficulty selector pre-selects **Hard** with no user action.

Verifiable via unit test: insert an entry, call `setDifficultyLabel(id:label:)`, fetch the entry, assert `difficultyLabel == .hard`.

---

### Scenario 6 — Review metadata footer

1. Set up a test entry with `lastReviewedDate = yesterday's date string` and `dueDate = tomorrow's date string`.
2. Display the card.

**Expected**:
- Metadata footer shows: "Last review: Yesterday"
- Metadata footer shows: "Next review: Tomorrow"

3. Set up a second entry with `lastReviewedDate = nil` and `dueDate = today's date string`.

**Expected**:
- Metadata footer shows: "Last review: Never"
- Metadata footer shows: "Next review: Today"

Verifiable via unit test on the relative date formatting function with fixed input strings.

---

### Scenario 7 — Focus Session completion screen

1. Set up exactly 3 due entries.
2. Start a Focus Session.
3. Rate the cards: Easy, Good, Hard (in order).

**Expected (after the third rating)**:
- The session completion screen appears.
- It shows: "You reviewed 3 words"
- It shows a rating breakdown: "Again: 0 · Hard: 1 · Good: 1 · Easy: 1"
- A dismiss action returns to the Learn tab's idle state.

Verifiable via unit test: initialise a `FocusSession` with 3 mock entries, call `recordRating` and `advance` three times, assert `isComplete == true` and tally values.

---

### Scenario 8 — Session pause and resume across tab switches

1. Start a Focus Session with 5 due cards.
2. Rate the first card.
3. Switch to the Inbox tab (do NOT close the sidebar).
4. Switch back to the Learn tab.

**Expected**:
- The session resumes at the second card (the one after the rated card).
- The progress counter reads "1 / 5".
- The first card (already rated) is not shown again.

---

### Scenario 9 — Rating write failure: retry re-queue

*Requires a test that injects a DB write failure.*

1. Trigger a rating write for a card while the repository is configured to fail (e.g., closed `DatabaseQueue`).

**Expected**:
- A transient inline error indicator appears on the current card.
- The session advances to the next card automatically.
- The failed card is appended to the **end** of the session queue.
- `ratedCount` does NOT increment for the failed card.
- When the failed card appears again at the end of the session, rating it successfully this time increments `ratedCount` and updates the database normally.

2. Trigger a second failure on the same card (second-time write also fails).

**Expected**:
- The inline error appears again.
- The card is **not** re-appended a second time.
- The session advances and completes without that card. The card retains its original `dueDate`.

---

### Scenario 10 — Empty queue state

**Prerequisites**: No entries with `dueDate ≤ today` and `triageStatus = 'saved'`.

1. Open the sidebar → Learn tab (or Review tab).

**Expected**:
- The card area is replaced by an empty state message (e.g., "Nothing to review today — come back tomorrow").
- No "Start Today's Review" button is shown.
- No session counter is shown.

---

### Scenario 11 — Migration v5 is non-destructive

1. Start with a database at `v4` (post-Epic 3) containing existing vocabulary entries.
2. Run `swift build && swift run` (or test setup) to trigger migration `v5`.

**Expected**:
- All existing entries are preserved with their original fields intact.
- Each existing entry now has `difficultyLabel = NULL` and `lastReviewedDate = NULL`.
- No existing column is modified or removed.

---

## References

- Interface contracts: [`contracts/learn-review-sessions.md`](contracts/learn-review-sessions.md)
- Data model: [`data-model.md`](data-model.md)
- Feature spec: [`spec.md`](spec.md)
- Epic 3 reference (SRS Engine, `applyRating`, `fetchDueEntries`): [`../008-srs-engine/quickstart.md`](../008-srs-engine/quickstart.md)
- Epic 3 contracts (extended by this feature): [`../008-srs-engine/contracts/srs-engine.md`](../008-srs-engine/contracts/srs-engine.md)
