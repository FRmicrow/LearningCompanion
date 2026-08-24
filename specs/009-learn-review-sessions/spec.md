# Learn & Review — Sessions de révision

**Feature ID**: Epic 4  
**Status**: Draft  
**Created**: 2025-07-23  
**Feature Directory**: `specs/009-learn-review-sessions`

---

## Clarifications

### Session 2025-07-23

- Q: When the user navigates away from an active Focus Session, what happens to their progress? → A: Save progress — the session is paused and resumes exactly where the user left off when they return to the Learn/Review tab.
- Q: When exactly is `difficultyLabel` persisted to the database? → A: Immediately on selector change — a separate, lightweight write fired as soon as the user taps Easy / Medium / Hard, independent of any rating write.
- Q: When a rating write fails during a Focus Session, how should the session handle the failed card? → A: Show inline error, re-queue at end — display a transient error indicator on the card, then move on; the failed card is appended to the end of the current session's queue for one retry.
- Q: Can a user run both a Learn session and a Review session on the same day's cards? → A: Single shared queue — a card rated in Learn is removed from Review too; users cannot revisit the same card in both modes the same day.
- Q: What should the session completion screen display beyond the total cards reviewed? → A: Cards reviewed count + a compact breakdown of ratings given during the session (Again / Hard / Good / Easy tallies).

---

## Overview

Implement two interactive study modes — **Learn** and **Review** — that surface the SRS engine's daily queue as an engaging, keyboard-first experience inside the native Learning Companion sidebar. The **Learn** view presents an English word and asks the user to recall its French translation before rating their performance (Again / Hard / Good / Easy). The **Review** view works in reverse: the French translation is shown first and the user recalls the English word, rating with Easy / Medium / Hard. Both modes are orchestrated by a **Focus Session** that chains all cards due today into a single continuous session with a live progress counter.

---

## Problem Statement

The SRS engine (Epic 3) computes a daily review queue and stores recall ratings, but there is currently no interface through which a user can actually conduct a study session. Saved vocabulary words surface in the Inbox but are never revisited in a structured, spaced way. Without a dedicated Learn and Review experience, the SRS engine has no input path — ratings are never generated, intervals are never updated, and words never progress toward mastery. The learning loop is broken at the point where it matters most: the user's daily practice.

---

## Goals

- Provide a **Learn view** where users actively recall word translations and rate their performance to drive the SRS engine.
- Provide a **Review view** (flashcard mode) that reverses the direction of recall, reinforcing retention from both angles.
- Provide a **Focus Session** that chains all due cards automatically into a single daily practice session with visible progress.
- Display **review metadata** (last reviewed, next review) on each card to give users a sense of progress over time.
- Show a **difficulty indicator** on each card so users can contextualise the relative challenge of a word.
- Ensure all interactions are accessible via keyboard shortcuts with no mouse required.

---

## Non-Goals

- This epic does not implement the SRS scheduling algorithm or data model (owned by Epic 3).
- This epic does not implement the Statistics dashboard (deferred to Epic 5).
- This epic does not introduce new capture or translation logic.
- Manual editing of a word or its translation is out of scope for this epic.
- Customisation of session length or card ordering strategy is out of scope.
- Audio pronunciation playback is out of scope.

---

## User Scenarios & Testing

### User Story 1 — Completing a Learn session card (Priority: P1)

The user opens the Learn tab in the sidebar. They see an English word at the top of the card and a "Reveal" button below it. The French translation is hidden. After attempting to recall the meaning, the user taps Space (or clicks Reveal) to uncover the translation. Four rating buttons appear: **Again**, **Hard**, **Good**, **Easy**. The user selects **Good**. The card disappears and the next due card is shown, with the progress counter incrementing.

**Why this priority**: This is the primary input path into the SRS engine. Every other feature in this epic depends on users being able to rate a card.

**Independent Test**: Render a Learn card with a known entry, trigger Reveal, submit a rating, and assert the next card is loaded and the progress counter increments by 1.

**Acceptance Scenarios**:

1. **Given** the daily queue has due entries, **When** the user opens the Learn tab, **Then** the first due entry is displayed with its English word visible and the French translation hidden.
2. **Given** a card is in its hidden state, **When** the user presses Space or clicks Reveal, **Then** the French translation is shown and the four rating buttons (Again / Hard / Good / Easy) become available.
3. **Given** the translation is revealed, **When** the user selects a rating, **Then** the rating is submitted to the SRS engine, the current card is dismissed, and the next card in the queue is displayed.
4. **Given** the user rates a card, **Then** the session progress counter increments by 1 (e.g., "3 / 12 cards").
5. **Given** all cards in the session have been rated, **When** the last card is dismissed, **Then** a session completion screen is shown.

---

### User Story 2 — Completing a Review session card (Priority: P1)

The user switches to the Review tab. A card shows the French translation at the top. The English word is hidden. The user recalls the English word and reveals it, then rates with **Easy**, **Medium**, or **Hard**.

**Why this priority**: Review mode reinforces recall from the translation direction, complementing the Learn mode and broadening retention.

**Independent Test**: Render a Review card, trigger Reveal, submit a rating, and assert the entry's SRS data is updated and the next card loads.

**Acceptance Scenarios**:

1. **Given** the user is in Review mode, **When** a card is displayed, **Then** only the French translation is visible; the English word is hidden.
2. **Given** a Review card is in its hidden state, **When** the user reveals the answer, **Then** the English word appears and the rating buttons (Easy / Medium / Hard) are shown.
3. **Given** a rating is submitted in Review mode, **Then** the card is dismissed, the SRS engine is updated, and the next card loads.
4. **Given** a Medium rating is submitted in Review mode, **Then** it maps to the **Good** SRS rating internally; Easy → Easy, Hard → Hard.

---

### User Story 3 — Running a Focus Session (Priority: P1)

The user opens the Learn tab and taps "Start Today's Review". The panel enters Focus Session mode and shows the header "Today's Review — 18 cards". Cards are presented one by one. After rating each card, the next appears automatically. A progress bar and counter ("5 / 18") update in real time. When the last card is rated, the session ends with a summary screen.

**Why this priority**: The Focus Session is the primary daily engagement loop of the entire application. It transforms individual card interactions into a coherent daily ritual.

**Independent Test**: Inject a queue of N cards, start a Focus Session, rate each card, and assert the counter reaches N/N and the completion screen appears.

**Acceptance Scenarios**:

1. **Given** the daily queue has N due cards, **When** the user starts a Focus Session, **Then** the session header shows "Today's Review — N cards" and the progress reads "0 / N".
2. **Given** a Focus Session is active, **When** the user rates a card, **Then** the counter increments by 1 and the next card is automatically displayed without user navigation.
3. **Given** a Focus Session is active, **When** the user rates the final card, **Then** a session completion screen appears showing the total number of cards reviewed.
4. **Given** a Focus Session is active, **When** a new card becomes due mid-session (edge case), **Then** the session continues with the already-loaded queue; the new card is not injected into the current session.
5. **Given** the daily queue is empty, **When** the user opens the Learn tab, **Then** an empty state is shown ("Nothing to review today — come back tomorrow") rather than a disabled Start button.

---

### User Story 4 — Reading review metadata on a card (Priority: P2)

While reviewing a card, the user sees "Last review: Yesterday" and "Next review: In 3 days" at the bottom of the card, giving them a sense of the word's review history and upcoming schedule.

**Why this priority**: Metadata provides transparency about the SRS schedule and reinforces the user's sense of long-term progress, increasing trust and motivation.

**Independent Test**: Render a card with known `lastReviewedDate` and `dueDate` values and assert the displayed strings match the expected human-readable format.

**Acceptance Scenarios**:

1. **Given** an entry has a `lastReviewedDate` set, **When** the card is displayed, **Then** the metadata footer shows "Last review: [relative date]" (e.g., "Yesterday", "3 days ago").
2. **Given** an entry has a `dueDate` set, **When** the card is displayed, **Then** the metadata footer shows "Next review: [relative date]" (e.g., "Tomorrow", "In 7 days").
3. **Given** an entry has never been reviewed (state = New), **When** the card is displayed, **Then** the metadata footer shows "Last review: Never" and "Next review: Today".

---

### User Story 5 — Setting the difficulty indicator on a card (Priority: P2)

Each card displays an Easy / Medium / Hard radio selector that persists the user's subjective difficulty assessment for the word — separate from the SRS rating. This label appears on future cards as context.

**Why this priority**: The difficulty indicator gives users a lightweight annotation tool that complements the algorithmic SRS rating without coupling to it.

**Independent Test**: Select a difficulty on a card, dismiss the card, re-open the entry in a future session, and assert the previously selected difficulty is shown pre-selected.

**Acceptance Scenarios**:

1. **Given** a card is displayed, **When** the user selects Easy, Medium, or Hard on the difficulty radio selector, **Then** the selection is persisted to the entry's record.
2. **Given** the user has previously set a difficulty for a word, **When** the same word appears in a future session, **Then** the radio selector is pre-filled with the previously saved value.
3. **Given** the user has not set a difficulty, **When** the card is displayed, **Then** no radio option is pre-selected; the selector is blank/neutral.

---

### Edge Cases

- **Queue becomes empty mid-session**: If all cards are rated during a Focus Session and the queue is drained, the session completion screen appears immediately — the queue does not reload mid-session.
- **Rating button pressed before Reveal**: Rating buttons are not accessible until the answer is revealed. Pressing the keyboard shortcut for a rating before Reveal is a no-op.
- **Rapid rating presses**: If the user presses a rating key multiple times before the next card loads, only the first press is registered. Subsequent presses are ignored until the next card is ready.
- **No cards due today**: An empty state view replaces the card area with a motivating message. The Focus Session button is not shown.
- **Single card in queue**: A session with exactly 1 card completes and shows the summary screen after a single rating.
- **Overdue words**: Words whose `dueDate` is in the past appear in the daily queue (handled by Epic 3). The Learn/Review session presents them without any visual distinction from today's cards.
- **App restart mid-session**: If the user quits the app while a Focus Session is in progress, the session state is not persisted. On relaunch, the Learn/Review tab shows the remaining due cards as a fresh queue (already-rated cards have updated `dueDate` values and no longer appear in the queue).
- **Rating write failure during Focus Session**: When a rating write fails, a transient inline error indicator is shown on the current card. The session then advances to the next card automatically; the failed card is appended once to the end of the session's queue for a single retry. If the retry also fails, the card is not re-appended again — it remains in the queue with its original `dueDate` and will reappear in a future session.

---

## Functional Requirements

### F-401 — Learn View

- The Learn view displays one card at a time drawn from the SRS daily review queue (Epic 3, F-303).
- Each card shows the **English word** prominently; the French translation is **hidden by default**.
- A **Reveal** button (and keyboard shortcut Space) uncovers the French translation.
- Once revealed, four **rating buttons** appear: **Again**, **Hard**, **Good**, **Easy**; each maps directly to the corresponding `SRSRating` value fed to the SRS engine.
- Submitting a rating triggers the F-304 persistence flow from Epic 3 and advances to the next card.
- Keyboard shortcuts for rating (after Reveal): `1` = Again, `2` = Hard, `3` = Good, `4` = Easy.
- The rating buttons must not be focusable or activatable by keyboard before Reveal is triggered.

### F-402 — Review View (Flashcards)

- The Review view displays one card at a time from the same SRS daily review queue.
- Each card shows the **French translation** prominently; the English word is hidden.
- A **Reveal** button (and keyboard shortcut Space) uncovers the English word.
- Once revealed, three **rating buttons** appear: **Easy**, **Medium**, **Hard**. They map to SRS ratings as: Easy → `easy`, Medium → `good`, Hard → `hard`.
- Submitting a rating triggers F-304 and advances to the next card.
- Keyboard shortcuts for rating (after Reveal): `1` = Easy, `2` = Medium, `3` = Hard.

### F-403 — Focus Session

- A **Focus Session** is initiated from the Learn or Review tab when due cards are available.
- The session header displays: "Today's Review — N cards" where N is the count of cards in the session at start time.
- A **progress counter** ("X / N") and optional progress bar update after each card is rated.
- Cards are presented in the order returned by the SRS daily review queue (F-303): overdue-first, then due-today.
- When all N cards are rated, a **session completion screen** appears showing: (1) total cards reviewed, and (2) a compact breakdown of ratings given during the session (e.g., Again: 2 · Hard: 4 · Good: 8 · Easy: 4). The session layer accumulates the rating tally in memory during the session; no additional database query is needed at completion time.
- The queue is captured at session start; cards that become due during the session are not injected mid-session.
- If no cards are due, the session cannot be started and an empty state is shown instead.
- **Session interruption**: If the user navigates to another tab (Inbox, Stats) or closes the sidebar panel while a Focus Session is active, the session is **paused** and its state (current card index, rated count, original card list) is preserved in memory for the lifetime of the app session. When the user returns to the Learn or Review tab, the session resumes exactly at the card where they left off. Rated cards are not re-presented. Session state is not persisted across app restarts — quitting and relaunching discards any in-progress session.
- **Write failure handling**: When a rating write fails for a card in the session, a transient inline error indicator is displayed on that card. The session advances to the next card automatically. The failed card is appended once to the end of the session queue for a single retry. If the retry write also fails, the card is not re-appended; it retains its original `dueDate` and reappears in a future session.

### F-404 — Difficulty Indicator

- Each card includes an **Easy / Medium / Hard radio selector** below the card content.
- Selecting a value **immediately** triggers a standalone database write — a separate, lightweight transaction that is independent of any SRS rating write. The write fires as soon as the user taps a difficulty option; no additional action (rating, card dismissal) is required.
- This field is independent of the SRS `srsState` and `easeFactor` — it is a user annotation only.
- On cards where no difficulty has been set, no option is pre-selected.
- The selector is always visible and interactive, regardless of whether the answer has been revealed.
- If the app is closed after a difficulty is set but before a rating is submitted, the `difficultyLabel` is preserved; the card remains in the queue with its SRS fields unchanged.

### F-405 — Review Metadata

- Each card displays a metadata footer with two fields:
  - **Last review**: relative date string computed from the entry's `lastReviewedDate` field (e.g., "Yesterday", "3 days ago", "Never").
  - **Next review**: relative date string computed from the entry's `dueDate` field (e.g., "Tomorrow", "In 7 days", "Today").
- Relative date strings use the device's local calendar. No UTC conversion is applied.
- The `lastReviewedDate` field on `VocabularyEntry` is updated to the current date each time a rating is successfully persisted.

---

## Success Criteria

1. A user can complete a full Focus Session — from pressing Start to seeing the completion screen — without touching the mouse; every interaction is reachable via keyboard shortcuts.
2. After rating a card, the next card appears within 200 ms on the same machine used for development (no artificial loading state required).
3. The progress counter reflects the correct count at all times during a session; it never skips or double-counts a card.
4. The daily queue is fully drained after a complete Focus Session (no due cards remain unless a new one became due during the session).
5. Review metadata (Last review, Next review) displays accurate relative dates on every card, verified by rendering cards with known fixed dates in tests.
6. A word set to difficulty Hard in one session retains that label in the next session without any additional user action.
7. Rating buttons cannot be activated before the Reveal action is triggered — verified by attempting to fire rating keyboard shortcuts on an unrevealed card and asserting no SRS write occurs.

---

## Key Entities

| Entity | Description |
|--------|-------------|
| `LearnView` | SwiftUI view rendering one card at a time in Learn mode (English → French recall). |
| `ReviewView` | SwiftUI view rendering one card at a time in Review mode (French → English recall). |
| `FocusSession` | Value type encapsulating the ordered list of cards, current index, and session start count. Immutable after session start. |
| `DifficultyLabel` | Enum with three values: `easy`, `medium`, `hard`. Persisted as a string column on `VocabularyEntry`. |
| `SessionCompletionView` | Summary screen shown when the last card in a Focus Session is rated. Displays total cards reviewed and a per-rating breakdown (Again / Hard / Good / Easy counts) sourced from the in-memory session tally. |
| `VocabularyEntry` (extended) | Gains `difficultyLabel` (optional) and `lastReviewedDate` (optional date) fields via GRDB migration. |

---

## Dependencies

- **Epic 3 — SRS Engine**: The daily review queue (F-303) is the data source for all card sessions. The rating persistence function (F-304) must be called on every card rating. Both must be complete before this epic can be integrated end-to-end.
- **Epic 1 — Vocabulary Sidebar**: The Learn and Review tabs are part of the multi-view navigation (F-102). The daily progress bar (F-103) consumes the queue count also used by F-403.
- **Epic 5 — Statistics**: The `lastReviewedDate` and `difficultyLabel` fields written by this epic feed the retention rate calculation (F-502) and the weak words list (F-504).

---

## Assumptions

- The daily review queue for Learn mode and Review mode draws from the **same** set of due entries. A word rated in either the Learn or Review tab is removed from the shared queue immediately; it will not appear in either mode again until its next `dueDate`. There is no per-mode queue — a single rating in any mode constitutes the day's review for that card.
- `difficultyLabel` is a user annotation and does **not** influence the SM-2 algorithm. It is persisted for display and Statistics purposes only.
- `lastReviewedDate` is set to the calendar date (date-only, no time component) of the most recent successful rating write.
- The session completion screen is a simple summary; no gamification, confetti, or audio effects are in scope for this epic.
- Session card order follows the queue priority from Epic 3 (overdue-first). Within a session, card order does not change once the session is started.
- The GRDB migration adding `difficultyLabel` and `lastReviewedDate` is additive and non-destructive; both columns default to `NULL` for existing entries.
