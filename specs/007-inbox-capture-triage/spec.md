# Inbox — Capture & Triage

**Feature ID**: Epic 2  
**Status**: Draft  
**Created**: 2025-07-21  
**Feature Directory**: `specs/007-inbox-capture-triage`

---

## Overview

Implement the **Inbox** view inside the Vocabulary Sidebar: the first surface a user sees when a new word is captured from the clipboard. The view presents the captured word, hides its translation by default, and gives the user three actions — **Save**, **Ignore**, and **Reveal** — to triage incoming vocabulary at their own pace. A badge on the menu-bar icon signals when new words are waiting.

---

## Problem Statement

Today, captured words are stored silently in the background with no immediate user-visible entry point. The user has no frictionless way to decide, word by word, which items deserve to enter their vocabulary list and which should be discarded. There is also no mechanism to reveal a translation on demand before committing to saving it. This gap reduces the quality of the vocabulary list and makes the capture pipeline feel opaque.

---

## Goals

- Give users a dedicated **first-touch triage surface** for every newly captured word.
- Let users **reveal the translation on demand** rather than having it immediately visible, encouraging active recall from the first encounter.
- Support **swipe gestures** consistent with macOS conventions (Mail.app model) as an alternative to buttons.
- Provide a **menu-bar badge** so users know at a glance when words are waiting without opening the sidebar.

---

## Non-Goals

- This epic does not implement the SRS learning algorithm (deferred to Epic 3).
- This epic does not implement Learn or Review sessions (deferred to Epic 4).
- This epic does not change clipboard capture or translation logic.
- Bulk triage (select-all, multi-select) is out of scope for this epic.
- The Inbox view shell and tab navigation are provided by Epic 1 (Vocabulary Sidebar); this epic populates the Inbox tab content only.

---

## User Scenarios & Testing

### User Story 1 — Reviewing and saving a new word (Priority: P1)

A French learner copies an English word they encountered while reading. The Vocabulary Sidebar is open on the Inbox tab. They see the word prominently displayed with its translation hidden. They tap **Reveal** to confirm the translation matches their expectation, then tap **Save** to add it to their vocabulary list.

**Why this priority**: This is the primary capture flow — without it, no word enters the learning pipeline. Every other feature in this epic is secondary to this core triage action.

**Independent Test**: Can be tested end-to-end by copying an English word, opening the Inbox tab, revealing the translation, and verifying the word appears in the vocabulary list after saving.

**Acceptance Scenarios**:

1. **Given** an English word has been captured and a translation is available, **When** the user opens the Inbox tab, **Then** the word is displayed prominently and the translation area shows a placeholder ("Tap to reveal" or equivalent).
2. **Given** the word is displayed in the Inbox, **When** the user taps **Reveal** or presses `Space`, **Then** the translation is shown in place of the placeholder.
3. **Given** the translation is visible, **When** the user taps **Save**, **Then** the word is added to the vocabulary list, removed from the Inbox, and the next pending word (if any) is shown.

---

### User Story 2 — Ignoring an irrelevant word (Priority: P2)

The user copies a word they already know well or that was captured accidentally. They want to dismiss it without it cluttering their vocabulary list.

**Why this priority**: Without an Ignore action, every captured word becomes noise in the learning pipeline. Triage quality depends on being able to discard items quickly.

**Independent Test**: Can be tested by copying a word, opening the Inbox, tapping Ignore, and verifying the word does not appear in the vocabulary list and the next item (or empty state) is shown.

**Acceptance Scenarios**:

1. **Given** a word is displayed in the Inbox, **When** the user taps **Ignore**, **Then** the word is removed from the Inbox queue and discarded (not saved to the vocabulary list).
2. **Given** the user ignores the last pending word, **When** the Inbox becomes empty, **Then** an elegant empty state is displayed.

---

### User Story 3 — Swiping words in the Inbox list (Priority: P3)

The user has several words queued in the Inbox. They want to triage quickly using swipe gestures familiar from Mail.app, without reaching for buttons.

**Why this priority**: Swipe gestures improve triage speed for users with a multi-touch trackpad but are not required for the core flow, which works with buttons alone.

**Independent Test**: Can be tested by populating the Inbox with multiple words, swiping left on one (Delete) and right on another (Known), and verifying the correct outcome for each.

**Acceptance Scenarios**:

1. **Given** the Inbox list has multiple words, **When** the user swipes left on a word, **Then** a **Delete** action is revealed and, if confirmed, the word is discarded.
2. **Given** the Inbox list has multiple words, **When** the user swipes right on a word, **Then** a **Known** action is revealed and, if triggered, the word is saved with a "known" status and removed from the Inbox.

---

### User Story 4 — Noticing pending words via the menu-bar badge (Priority: P4)

The user is working in another application. Without opening the sidebar, they glance at the menu bar and notice the Learning Companion icon has a badge indicating 3 words are waiting in the Inbox.

**Why this priority**: The badge is a passive awareness signal. Users who keep the sidebar closed still benefit from knowing when vocabulary has been captured.

**Independent Test**: Can be tested by copying words while the sidebar is closed and verifying the menu-bar icon badge count increments. Clearing the Inbox should remove the badge.

**Acceptance Scenarios**:

1. **Given** one or more words are pending in the Inbox, **When** the user looks at the menu-bar icon, **Then** a badge displaying the count of pending words is visible on the icon.
2. **Given** the Inbox is empty, **When** the user looks at the menu-bar icon, **Then** no badge is displayed.

---

### Edge Cases

- What happens when a word is captured while the Inbox view is open? The new word should appear immediately without requiring a manual refresh.
- What happens when the translation for a word is still pending (not yet computed)? The Reveal action should show a loading indicator instead of an empty string, and the Save action should still be available.
- What happens if the user rapidly captures the same word multiple times? The Inbox should deduplicate — the word appears once.
- What happens when the user taps Reveal on a word whose translation subsequently fails? An error state ("Translation unavailable") should be shown rather than an empty translation field.

---

## Requirements

### Functional Requirements

- **FR-001**: The Inbox tab MUST display all vocabulary entries with status `pending` (captured but not yet triaged by the user).
- **FR-002**: For each pending entry, the translation MUST be hidden by default; only the source word is shown.
- **FR-003**: The user MUST be able to reveal the translation for the focused entry by tapping a **Reveal** button or pressing `Space`.
- **FR-004**: The user MUST be able to save the focused entry to the vocabulary list by tapping **Save**; the entry is then removed from the Inbox queue.
- **FR-005**: The user MUST be able to ignore the focused entry by tapping **Ignore**; the entry is discarded and removed from the Inbox queue.
- **FR-006**: Swiping left on an Inbox list item MUST expose a **Delete** destructive action.
- **FR-007**: Swiping right on an Inbox list item MUST expose a **Known** action that saves the entry with a "known" status.
- **FR-008**: The menu-bar icon MUST display a badge with the count of pending Inbox entries when the count is greater than zero.
- **FR-009**: The badge MUST be removed when the Inbox queue is empty.
- **FR-010**: New entries arriving while the Inbox view is open MUST appear without requiring a manual refresh (live update via the existing GRDB `ValueObservation` mechanism).
- **FR-011**: Duplicate captures of the same source word MUST be deduplicated; only one entry per word appears in the Inbox at a time.

### Key Entities

- **Inbox Entry**: A vocabulary entry in the `pending` triage state. Key attributes: source word, translation (may be blank/loading), capture timestamp.
- **Triage Action**: One of Save, Ignore, Known — the outcome the user assigns to an Inbox entry.
- **Badge Count**: A non-persistent integer derived from the count of pending Inbox entries; drives the menu-bar icon badge.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: A user can triage (save or ignore) a newly captured word within 5 seconds of opening the Inbox tab, using only keyboard shortcuts.
- **SC-002**: The menu-bar badge updates within 1 second of a new word being captured or an Inbox entry being cleared.
- **SC-003**: The Inbox list reflects the current pending entry count accurately after every triage action, with no stale entries remaining visible.
- **SC-004**: Swipe actions complete and the list updates within 300 ms of the gesture being recognized.
- **SC-005**: The Inbox empty state is displayed correctly after the last pending entry is triaged, with no residual data visible.

---

## Assumptions

- The Vocabulary Sidebar panel and Inbox tab shell are provided by Epic 1; this epic only populates the Inbox tab content.
- "Pending" entries are vocabulary items captured by the clipboard pipeline that have not yet been explicitly saved or ignored by the user — this aligns with the existing `VocabularyEntry` model stored via `VocabularyEntryRepository`.
- The translation for a newly captured word may already be available (set by `TranslationService`) or still computing (`.pending` translation state); the Inbox must gracefully handle both states.
- The daily-progress bar (F-103 from Epic 1) counts words saved from the Inbox as part of the daily progress total.
- Swipe gestures require a trackpad or magic mouse; no fallback gesture is required for users without multi-touch input (buttons provide the same actions).
- Multi-monitor support is out of scope; the badge appears on the menu-bar icon of the primary display.
- Bulk triage operations (multi-select, clear-all) are deferred; users triage one word at a time in this epic.
- The constitution's privacy constraint (Principle I) means the Inbox never transmits word data off-device; all state is local.
- The menu-bar badge count is derived live from the repository — it is not persisted independently.
