# SRS Engine — Spaced Repetition

**Feature ID**: Epic 3  
**Status**: Draft  
**Created**: 2025-07-22  
**Feature Directory**: `specs/008-srs-engine`

---

## Clarifications

### Session 2025-07-22

- Q: What distinguishes `new` from `learning` in the SRS state model? → A: `new` = entry has never been rated (0 ratings); `learning` = rated ≥ 1 time AND `interval < 7`.
- Q: How is `interval` stored — floating-point or integer? → A: Stored as floating-point; rounded to nearest whole day only when computing `dueDate`.
- Q: What happens when a rating write fails? → A: Show an in-session error indicator; re-queue the entry for the current session without automatic retry.
- Q: How quickly must the daily queue reflect a rating write? → A: Within 500 ms of a successful write.

---

## Overview

Implement a **Spaced Repetition System (SRS) engine** that tracks the learning state of every vocabulary entry and automatically schedules the next review for each word. When a user rates their recall (Easy / Good / Hard / Again), the engine recalculates the optimal next review interval and persists it to the local database. The engine drives the Learn and Review views (Epic 4) and the Statistics dashboard (Epic 5) by exposing a daily review queue of all entries that are due today.

---

## Problem Statement

Today, the application stores vocabulary words but has no mechanism for long-term retention. Saved words are never surfaced again in a structured way — they accumulate silently and the user has no signal about which words they actually know, which they are struggling with, or when to revisit them. Without a retention mechanism, the tool functions as a word list rather than a learning system. Users who want to move vocabulary from short-term exposure to long-term memory have no support for doing so.

---

## Goals

- Equip every vocabulary entry with an SRS state that progresses from **New → Learning → Known → Mastered**.
- Implement an automatic scheduling algorithm that computes the next review date based on user recall ratings.
- Expose a **daily review queue** containing all entries due for review today or earlier.
- Persist all SRS data locally so that progress is retained across app restarts.
- Provide the foundation on which Epic 4 (Learn & Review sessions) and Epic 5 (Statistics) are built.

---

## Non-Goals

- This epic does not implement the visual Learn or Review session interfaces (deferred to Epic 4).
- This epic does not implement the Statistics dashboard (deferred to Epic 5).
- This epic does not change clipboard capture, translation, or Inbox triage logic.
- Manual override of SRS state (e.g., resetting a word to New) is out of scope for this epic.
- Cloud sync or cross-device state sharing is out of scope.
- The algorithm parameters (initial interval, ease factor boundaries, etc.) are not user-configurable in this epic.

---

## User Scenarios & Testing

### User Story 1 — Rating a word during a review session (Priority: P1)

The user is in the Learn view (provided by Epic 4). They see an English word and attempt to recall its French translation. After revealing the answer, they rate their recall as **Good**. The app immediately schedules the next review for that word in 3 days and removes it from today's review queue.

**Why this priority**: The rating-and-reschedule loop is the core value of the SRS. Everything else — querying the queue, displaying stats — depends on this write path working correctly.

**Independent Test**: Can be tested by programmatically setting an entry to a known SRS state, calling the rating function with a specific value, and asserting the resulting `dueDate` and `interval` match the expected algorithm output.

**Acceptance Scenarios**:

1. **Given** a vocabulary entry with a known current state and interval, **When** the user rates it **Easy**, **Then** the entry's `interval` increases significantly (next review far in the future) and `dueDate` is set accordingly.
2. **Given** a vocabulary entry, **When** the user rates it **Good**, **Then** the interval increases moderately and `dueDate` is set to today + new interval.
3. **Given** a vocabulary entry, **When** the user rates it **Hard**, **Then** the interval increases only slightly (or stays at the minimum threshold) and `dueDate` is set to a near-future date.
4. **Given** a vocabulary entry, **When** the user rates it **Again**, **Then** the interval resets to 1 day and `dueDate` is set to tomorrow, regardless of prior progress.
5. **Given** any rating is submitted, **Then** the rating and updated SRS fields are immediately persisted to the local database with no data loss on restart.

---

### User Story 2 — Seeing today's review queue (Priority: P1)

The user opens the sidebar at the start of their day. The Learn tab badge (or the daily progress bar) shows that 12 words are due for review today. When they start a Focus Session, those 12 words are presented in sequence.

**Why this priority**: Without an accurate daily queue, the entire review session (Epic 4) has no data source. This query is the interface between the SRS engine and the Learn/Review UIs.

**Independent Test**: Can be tested by inserting entries with varying `dueDate` values and asserting that only entries where `dueDate ≤ today` are returned by the queue query.

**Acceptance Scenarios**:

1. **Given** the database contains entries with `dueDate ≤ today`, **When** the daily queue is requested, **Then** all such entries are returned, sorted by priority (overdue entries first, then due-today entries).
2. **Given** the database contains entries with `dueDate > today`, **When** the daily queue is requested, **Then** those entries are NOT included.
3. **Given** a word is rated and its `dueDate` is set to a future date, **When** the daily queue is requested on the same day, **Then** that word no longer appears in the queue.

---

### User Story 3 — A newly saved word enters the SRS pipeline (Priority: P2)

A user saves a word from the Inbox (Epic 2). The word immediately has an SRS state of **New** and a `dueDate` of today, making it eligible to appear in today's review queue.

**Why this priority**: New words must enter the queue automatically so users do not need to manually schedule them. This ensures the pipeline is seamless from capture to review.

**Independent Test**: Can be tested by saving an Inbox entry and asserting that the resulting `VocabularyEntry` has `srsState = .new` and `dueDate = today`.

**Acceptance Scenarios**:

1. **Given** a word is saved from the Inbox, **When** its `VocabularyEntry` is written to the database, **Then** it has `srsState = .new`, `dueDate = today`, `interval = 1`, and a default `easeFactor`.
2. **Given** a new entry exists with `dueDate = today`, **When** the daily queue is queried, **Then** the new entry appears in the queue.

---

### User Story 4 — SRS state progresses through the lifecycle (Priority: P2)

Over multiple review sessions across several days, a word progresses from **New** to **Learning** to **Known** to **Mastered** as the user consistently rates it positively.

**Why this priority**: The state machine defines the word's lifecycle and is used by the Statistics dashboard and filtering logic in future epics.

**Independent Test**: Can be tested by simulating a sequence of ratings over multiple intervals and asserting the `srsState` transitions at the correct thresholds.

**Acceptance Scenarios**:

1. **Given** a word in state **New** (zero prior ratings), **When** it is rated for the first time, **Then** its state advances to **Learning** (rated ≥ 1, interval < 7).
2. **Given** a word in state **Learning**, **When** a positive rating raises its interval to ≥ 7 days, **Then** its state advances to **Known**.
3. **Given** a word in state **Known**, **When** a positive rating raises its interval to ≥ 21 days, **Then** its state advances to **Mastered**.
4. **Given** a word in any non-New state, **When** the user rates it **Again**, **Then** its interval resets to 1 and its state reverts to **Learning** (since it now has ≥ 1 rating but interval < 7).

---

### Edge Cases

- **Overdue entries**: A word whose `dueDate` is in the past (e.g., the user took a week off) appears in the daily queue and is prioritised for review. Its overdue duration does not artificially inflate its interval when rated.
- **All words mastered**: When no entries have `dueDate ≤ today`, the daily queue is empty and the Epic 4 UI shows a "Nothing due today" state.
- **Concurrent rating**: If the user triggers a rating while a previous rating is being persisted, the second rating must not overwrite or corrupt the first write. Operations are serialised.
- **First-ever rating**: A word that has never been rated (state = New, interval = 1) follows the algorithm from its initial defaults without requiring any prior history.
- **Rating write failure**: If the database transaction for a rating write fails, the error is surfaced to the user via an in-session error indicator (e.g., a transient message in the Learn/Review view). The rated entry is re-queued for the current review session so the user can rate it again. No automatic retry is performed. The entry's SRS fields are not mutated in memory until the write succeeds.

---

## Functional Requirements

### F-301 — SRS Data Model

- The `VocabularyEntry` entity gains four new fields persisted to the local database:
  - `srsState`: one of `new`, `learning`, `known`, `mastered`.
  - `dueDate`: the calendar date on which the entry is next due for review.
  - `interval`: the current review interval, expressed in days, stored as a floating-point number.
  - `easeFactor`: a multiplier that adjusts interval growth based on recall history.
- Existing `VocabularyEntry` records receive default values on migration: `srsState = new`, `dueDate = today`, `interval = 1`, `easeFactor = 2.5`.
- The migration must be additive and non-destructive — no existing data is modified beyond adding the new columns with defaults.

### F-302 — Spaced Repetition Algorithm

- The engine implements the **SM-2** scheduling algorithm:
  - On **Again**: interval resets to 1 day; `easeFactor` decreases by 0.2 (minimum 1.3).
  - On **Hard**: interval multiplies by 1.2; `easeFactor` decreases by 0.15.
  - On **Good**: interval multiplies by current `easeFactor`.
  - On **Easy**: interval multiplies by `easeFactor × 1.3`.
- The minimum interval after any non-Again rating is 1.0 day.
- `interval` is stored as a floating-point number; fractional values accumulate across ratings. When computing `dueDate`, the interval is rounded to the nearest whole number of calendar days before adding to today.
- `dueDate` is always set to `today + round(interval)` (calendar days, not hours).
- `srsState` transitions follow these rules:
  - `new`: entry has never been rated (zero ratings submitted).
  - `learning`: entry has been rated ≥ 1 time AND `interval < 7`.
  - `known`: `interval ≥ 7`.
  - `mastered`: `interval ≥ 21`.
- The algorithm is a pure function: given current state + rating → new state. It has no side effects beyond returning updated values; persistence is handled separately.

### F-303 — Daily Review Queue

- The repository exposes a query that returns all `VocabularyEntry` records where `dueDate ≤ today`.
- Results are ordered by: overdue entries first (oldest `dueDate` first), then entries due today.
- The query is reactive: it must support GRDB `ValueObservation` so the Learn/Review views in Epic 4 can observe queue changes in real time.
- The queue count is exposed as a single integer for use by the daily progress bar (Epic 1) and the session header in Epic 4.

### F-304 — Rating Persistence

- When the user submits a rating (Easy / Good / Hard / Again) for an entry, the engine:
  1. Runs the SM-2 algorithm to compute new `interval`, `dueDate`, `easeFactor`, and `srsState`.
  2. Writes all four updated fields to the database in a single atomic transaction.
  3. Returns the updated entry to the caller on success.
- A rating write must complete within 100 ms as perceived by the caller.
- The rating is never queued or deferred — it is committed synchronously within the same database transaction.
- **On write failure**: the caller receives an error result; the entry's SRS fields are not mutated; the Learn/Review view (Epic 4) surfaces an in-session error indicator and re-queues the entry for the current session. No automatic retry is performed.

---

## Success Criteria

1. After submitting a rating, the word's `dueDate` is updated in the database within 100 ms and the daily queue reflects the change within 500 ms of a successful write.
2. The daily review queue contains exactly the set of entries with `dueDate ≤ today` — no more, no fewer — verified by inserting test data with known dates.
3. A word rated **Again** always returns to a 1-day interval regardless of its prior state.
4. A word progresses from **New** to **Mastered** through a sequence of positive ratings consistent with the SM-2 thresholds, verifiable in unit tests without any UI.
5. All SRS field values survive an app restart without data loss or corruption.
6. Adding the four new SRS columns via migration does not delete or corrupt any existing vocabulary entries.

---

## Key Entities

| Entity | Description |
|--------|-------------|
| `SRSState` | Enum with four values: `new`, `learning`, `known`, `mastered`. Persisted as a string column. |
| `SRSRating` | Enum with four values: `again`, `hard`, `good`, `easy`. Input to the scheduling algorithm. |
| `SRSEngine` | Pure-function scheduling service: takes a current entry + rating, returns updated SRS fields. |
| `VocabularyEntry` (extended) | Gains `srsState`, `dueDate`, `interval`, `easeFactor` columns via GRDB migration. |
| `DailyReviewQueue` | GRDB query result: all entries where `dueDate ≤ today`, ordered by overdue-first priority. |

---

## Dependencies

- **Epic 1** (Vocabulary Sidebar): provides the panel and daily progress bar that will consume the queue count from F-303.
- **Epic 2** (Inbox): the Save action must set default SRS fields on new entries (F-301 default values).
- **Epic 4** (Learn & Review sessions): consumes the daily review queue (F-303) and triggers the rating persistence flow (F-304).
- **Epic 5** (Statistics dashboard): reads `srsState` and `easeFactor` to compute retention rates and identify weak words.
- The existing `VocabularyEntryRepository` and GRDB migration infrastructure are extended — not replaced.
- GRDB `Column("fieldName")` keys must match the exact SQL column names declared in the new migration (`srsState`, `dueDate`, `interval`, `easeFactor`).

---

## Assumptions

- The SM-2 algorithm parameters (initial `easeFactor = 2.5`, minimum `easeFactor = 1.3`, `easeFactor` penalty/bonus values) are fixed defaults; they are not user-configurable in this epic.
- `dueDate` is stored as a calendar date (date-only, no time component) to avoid timezone edge cases.
- "Today" is resolved at query time using the device's local calendar — no UTC conversion is applied.
- Words saved from the Inbox always enter the SRS with `dueDate = today`, making them immediately eligible for the day's review queue.
- The SRS engine is a pure, synchronous function — it does not perform I/O. Callers are responsible for persistence.
- The migration adds four nullable columns with server-side defaults; no `NOT NULL` constraint is added, to keep the migration non-breaking for any in-flight app state during upgrade.
- Overdue words (missed reviews) do not receive a bonus or penalty beyond their normal SM-2 calculation on the day they are finally reviewed.
