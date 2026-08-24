# Feature Specification: Inbox Word Management & Learn Session Control

**Feature Branch**: `010-inbox-word-management`

**Created**: 2025-07-25

**Status**: Draft

**Input**: User description: "Dans l'onglet 'boite de réception' je veux pouvoir supprimer les mots que je sélectionne. Je veux pouvoir sélectionner des mots et les ajouter à 'apprendre' - Je veux pouvoir recommencer une session 'apprendre' -> Si plus de 20 mots, faire un random sur la liste -> Si je coche 'easy' c'est que le mot est validé et n'a plus besoin d'être présent."

---

## Overview

Extend the **Inbox** tab with multi-select capability so users can delete words in bulk or promote them directly into a Learn session queue. Extend the **Learn** session with a **Restart** action that starts a fresh session from the current available pool — randomly sampling up to 20 cards when the pool exceeds that threshold. Finally, formalise the **Easy** rating in a Learn session as a **mastery signal**: a word rated Easy is considered fully learned and is permanently removed from the daily queue.

---

## Problem Statement

Users accumulate words in the Inbox but currently have no way to act on multiple words at once — each word must be triaged individually (Epic 2). There is also no direct path from Inbox to a Learn session: users cannot cherry-pick words they want to study right now. Additionally, a completed Learn session cannot be restarted for another pass without restarting the app or waiting for the next day's queue. Finally, the Easy rating does not carry a permanent "mastered" signal — there is no way for a word to graduate out of the daily queue based on user confidence, leaving the queue perpetually populated even for words the user knows perfectly.

---

## Goals

- Allow users to **multi-select words in the Inbox** and delete them in one action.
- Allow users to **multi-select words in the Inbox and promote them to a Learn session** on demand.
- Allow users to **restart a Learn session** at any time using the current available word pool.
- When the pool for restart exceeds 20 words, **randomly sample 20 words** to keep the session manageable.
- Define **Easy = mastered**: a word rated Easy in Learn mode is permanently retired from the daily queue.

---

## Non-Goals

- Multi-select in the Review (flashcard) tab is out of scope.
- Editing or translating words from the Inbox is out of scope (existing Epic 2 behaviour is unchanged).
- Undo / restore after a bulk delete is out of scope for this iteration.
- The random sampling seed is not user-configurable; it is system-random.
- Statistics or mastery tracking dashboards (deferred to Epic 5) are out of scope.
- Changing the behaviour of the Again / Hard / Good ratings in Learn mode is out of scope.

---

## User Scenarios & Testing

### User Story 1 — Bulk-deleting words from the Inbox (Priority: P1)

The user opens the Inbox tab and sees several words they no longer care about. They tap a **Select** button to enter selection mode, tap checkboxes next to the unwanted words, then tap **Delete Selected**. The selected words disappear from the Inbox immediately.

**Why this priority**: Bulk delete is the fastest way to clean up inbox noise. Without it, users must dismiss words one by one — friction that discourages regular triage.

**Independent Test**: Populate the Inbox with N words, enter selection mode, select a subset, confirm delete, and assert only the non-selected words remain in the Inbox.

**Acceptance Scenarios**:

1. **Given** the Inbox has words, **When** the user taps **Select**, **Then** selection mode is activated: a checkbox appears next to each word and a toolbar shows **Delete Selected** (disabled) and **Cancel**.
2. **Given** selection mode is active, **When** the user taps a word's checkbox, **Then** the word is marked selected and **Delete Selected** becomes enabled.
3. **Given** one or more words are selected, **When** the user taps **Delete Selected**, **Then** all selected words are permanently removed from the Inbox and the Inbox list updates immediately.
4. **Given** selection mode is active, **When** the user taps **Cancel**, **Then** selection mode exits and no words are deleted.
5. **Given** the last word in the Inbox is deleted via bulk delete, **When** the Inbox becomes empty, **Then** the empty state view is displayed.

---

### User Story 2 — Promoting Inbox words to a Learn session (Priority: P1)

The user sees three new words in the Inbox that they want to study now. They enter selection mode, select those three words, tap **Add to Learn**, and the Learn tab opens with a focused session containing only those words.

**Why this priority**: This is the primary "on-demand learning" flow. It bridges the capture pipeline to the study experience without waiting for the SRS scheduler.

**Independent Test**: Select K words in the Inbox, tap Add to Learn, open the Learn tab, and assert the session contains exactly those K words in a fresh session.

**Acceptance Scenarios**:

1. **Given** selection mode is active and one or more words are selected, **When** the user taps **Add to Learn**, **Then** the selected words are queued for a fresh Learn session and the app navigates to the Learn tab.
2. **Given** the Learn tab opens after an **Add to Learn** action, **When** the session starts, **Then** only the promoted words are in the session queue; no SRS-scheduled cards are mixed in.
3. **Given** the **Add to Learn** action completes, **Then** the promoted words remain in the Inbox (they are not automatically saved or deleted — triage is still the user's responsibility).
4. **Given** selection mode is active but no words are selected, **Then** the **Add to Learn** button is disabled.

---

### User Story 3 — Restarting a Learn session (Priority: P2)

The user has just completed a Learn session and wants another pass. They tap **Restart Session** on the completion screen (or in the Learn tab header). A new session begins. If the available pool has more than 20 words, 20 are randomly sampled; otherwise all available words are used.

**Why this priority**: Repeated practice in a single sitting reinforces retention. Without Restart, users are blocked until the next day's queue, reducing the app's utility for intensive study.

**Independent Test**: Complete a session, trigger Restart, and assert a new session starts with min(pool size, 20) cards drawn from the current available pool.

**Acceptance Scenarios**:

1. **Given** a Learn session has ended, **When** the user taps **Restart Session**, **Then** a new session starts immediately using the current available word pool.
2. **Given** the available pool has 20 or fewer words, **When** the session is restarted, **Then** all available words are included in the new session.
3. **Given** the available pool has more than 20 words, **When** the session is restarted, **Then** exactly 20 words are randomly sampled from the pool and used as the new session queue.
4. **Given** a Restart is triggered from a promoted Inbox session (User Story 2), **When** the pool exceeds 20, **Then** the random sample draws from the full pool of available Learn words (not just the originally promoted ones).
5. **Given** the available pool is empty (all words have been mastered or none remain), **When** the user attempts to restart, **Then** the empty state view is shown and no session is started.

---

### User Story 4 — Marking a word as mastered via Easy rating (Priority: P1)

The user rates a word **Easy** during a Learn session. The word is marked as mastered and will no longer appear in the daily SRS queue or in future Learn sessions.

**Why this priority**: Without a mastery signal, words accumulate indefinitely even after a user knows them perfectly. Easy-as-mastery is the exit mechanism for the learning pipeline.

**Independent Test**: Rate a word Easy in a Learn session, then assert the word does not appear in the next SRS daily queue query and is excluded from future Learn sessions.

**Acceptance Scenarios**:

1. **Given** a word is displayed in a Learn session, **When** the user rates it **Easy**, **Then** the word's record is updated to reflect a mastered state.
2. **Given** a word is in a mastered state, **When** the SRS engine computes the next daily queue, **Then** the mastered word is excluded from the queue.
3. **Given** a word is mastered, **When** a Learn session (including a restarted session) is constructed, **Then** the mastered word is not included.
4. **Given** a word is mastered, **Then** it remains visible in the general vocabulary list (e.g., the Inbox or saved words list) but is visually distinguished as mastered (e.g., a label or icon) so the user can see their progress.

---

### Edge Cases

- **Selecting all words and deleting**: If the user selects all Inbox words and deletes them, the Inbox empties and shows its empty state.
- **Promoting already-mastered words to Learn**: If a selected word is already mastered, it is included in the promoted session (the user explicitly asked for it). It is not re-mastered — rating it Easy again is a no-op on its mastery state.
- **Restart with no eligible words**: If all Learn-eligible words have been mastered, the Restart action shows the empty state instead of starting a session.
- **Inbox selection mode and live captures**: If a new word is captured while selection mode is active, it appears in the list without a checkbox pre-selected.
- **Add to Learn with a session already in progress**: If a Learn session is already paused (per Epic 4 Focus Session interruption rules), the **Add to Learn** action replaces the paused session with the newly promoted session. The previously paused session is discarded.
- **Pool boundary at exactly 20**: A pool of exactly 20 words results in all 20 being included — random sampling only applies when the pool exceeds 20.

---

## Requirements

### Functional Requirements

- **FR-001**: The Inbox tab MUST provide a **Select** toggle that activates multi-selection mode on the word list.
- **FR-002**: In selection mode, each word MUST display a checkbox. The user MUST be able to tap a word row to toggle its selection state.
- **FR-003**: In selection mode, a **Delete Selected** action MUST be available and MUST be disabled when no words are selected.
- **FR-004**: Tapping **Delete Selected** MUST permanently remove all selected words from the Inbox (they are discarded, not saved).
- **FR-005**: In selection mode, an **Add to Learn** action MUST be available and MUST be disabled when no words are selected.
- **FR-006**: Tapping **Add to Learn** MUST create a fresh on-demand Learn session containing only the selected words, then navigate to the Learn tab.
- **FR-007**: Words promoted via **Add to Learn** MUST remain in the Inbox after the action; they are not deleted or saved automatically.
- **FR-008**: Selection mode MUST be exitable via a **Cancel** action that clears all selections and returns to normal Inbox view.
- **FR-009**: The Learn tab and the session completion screen MUST expose a **Restart Session** action.
- **FR-010**: Tapping **Restart Session** MUST build a new session from the current Learn-eligible word pool (non-mastered, available words).
- **FR-011**: When the Learn-eligible pool exceeds 20 words, the Restart MUST randomly sample exactly 20 words without replacement from that pool.
- **FR-012**: When the Learn-eligible pool is 20 or fewer words, the Restart MUST include all words in the new session.
- **FR-013**: Rating a word **Easy** during a Learn session MUST mark the word as **mastered** in its persistent record.
- **FR-014**: Mastered words MUST be excluded from all future SRS daily queue computations.
- **FR-015**: Mastered words MUST be excluded from all future Learn session queues, including restarted sessions.
- **FR-016**: Mastered words MUST remain visible in the vocabulary list and MUST be visually distinguished from non-mastered words.

### Key Entities

- **Selection State**: Transient UI state tracking which Inbox words are currently checked. Not persisted to the database.
- **On-Demand Learn Session**: A Learn session constructed from a user-selected word subset rather than from the SRS daily queue. Follows the same Focus Session mechanics defined in Epic 4 (F-403).
- **Mastered Word**: A vocabulary entry whose mastery flag has been set to `true` via an Easy rating. Excluded from future queues.

---

## Success Criteria

- **SC-001**: A user can select and delete 5 Inbox words in under 10 seconds using only tap interactions.
- **SC-002**: After tapping **Add to Learn**, the Learn tab opens and the promoted words are the only cards in the session — no SRS cards are mixed in.
- **SC-003**: A restarted session with a pool of more than 20 words contains exactly 20 randomly sampled cards; the same restart triggered twice produces different orderings with high probability.
- **SC-004**: A word rated Easy never appears again in the daily queue, verified by asserting it is absent from subsequent queue queries in automated tests.
- **SC-005**: Mastered words are visually distinguishable in the vocabulary list from non-mastered words without opening a word's detail.
- **SC-006**: Entering and exiting selection mode does not trigger any database writes.

---

## Assumptions

- The Inbox word list for multi-select is the same list as the existing pending/triaged word list from Epic 2. No new data source is introduced.
- "Available Learn pool" for Restart means all non-mastered vocabulary entries that have been saved (not pending triage) — the same set the SRS engine draws from, minus mastered words.
- Mastery is a one-way transition in this iteration: a word marked mastered cannot be un-mastered through the UI (deferred to a future spec).
- The `mastered` flag is stored as a boolean column on `VocabularyEntry` via an additive GRDB migration (forward-only, defaults to `false` for existing entries).
- On-demand Learn sessions (promoted from Inbox) do not write SRS rating data back to the database differently from regular sessions — the same F-304 rating persistence flow from Epic 3 applies.
- Random sampling uses the system random number generator (`Swift.shuffle()` or equivalent); no seed control is provided.
- The **Add to Learn** action replaces any currently paused Focus Session (per Epic 4 session interruption rules). The user is not warned — the paused session is simply discarded.
- The constitution's privacy constraint (Principle I) is unaffected: all new state (mastery flag, selection state) is local-only.
- The constitution's test discipline (Principle III) applies: all new logic (mastery exclusion, random sampling, selection state transitions) MUST be covered by Swift Testing unit tests.
