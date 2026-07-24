# Feature Specification: Vocabulary Panel UI

**Feature Branch**: `002-vocabulary-panel-ui`

**Created**: 2025-07-22

**Status**: Draft

**Input**: User description: "Je veux que le panel soit affiché à gauche de l'écran avec les données suivantes — <DATE> - <Retry traduction button> - Mot -> Traduction - Mot2 -> Traduction. Je veux pouvoir cocher les mots retenus avec un coche « ok ». Je veux pouvoir voir dans une liste séparée les mots anciens (+1 semaine) non retenus"

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Review Today's Vocabulary (Priority: P1)

The user opens the application and sees a left-side panel displaying the vocabulary words captured on each date. Each date group shows a "Retry Translation" button alongside its date heading, then lists each captured word paired with its translation. The user can mark individual words as retained by checking them off.

**Why this priority**: This is the core vocabulary review interaction — without it, no learning progress can be tracked or acted upon.

**Independent Test**: Can be fully tested by launching the app with at least one captured word, observing the panel on the left side of the screen, and verifying that date groups, word→translation pairs, and checkboxes are all visible and functional.

**Acceptance Scenarios**:

1. **Given** the app has captured vocabulary entries for today, **When** the panel is displayed, **Then** entries are grouped under today's date heading, each showing the word, its translation, and an unchecked "ok" checkbox.
2. **Given** a word is visible in the panel, **When** the user checks its "ok" checkbox, **Then** the word is visually marked as retained (checkbox becomes checked and the word is styled distinctly).
3. **Given** a word was previously marked as retained, **When** the panel is reopened, **Then** the word's retained state is still checked.

---

### User Story 2 - Retry Translation for a Date Group (Priority: P2)

The user sees that one or more translations in a date group are missing or incorrect and clicks the "Retry Translation" button for that group to re-trigger the translation process for all untranslated words in that group.

**Why this priority**: Translation errors or failures are expected and users need a quick recovery path without re-copying words from the clipboard.

**Independent Test**: Can be fully tested by placing a word with a missing translation in a date group and confirming the Retry button triggers a new translation attempt and updates the displayed result.

**Acceptance Scenarios**:

1. **Given** a date group contains one or more words with missing or failed translations, **When** the user clicks "Retry Translation", **Then** the system re-attempts translation for those words and updates the displayed translations upon completion.
2. **Given** all words in a date group already have translations, **When** the user clicks "Retry Translation", **Then** the system re-attempts translation for all words in that group (refreshes translations).
3. **Given** the retry is in progress, **When** the panel displays, **Then** a loading indicator is shown and the button is disabled until the operation completes.

---

### User Story 3 - Review Old Unretained Words (Priority: P3)

The user wants to review vocabulary words that were captured more than one week ago and have never been marked as retained. These words are displayed in a separate, clearly labelled list below (or distinct from) the current vocabulary list.

**Why this priority**: Spaced repetition requires surfacing forgotten or unlearned words; this list ensures no old vocabulary is silently lost.

**Independent Test**: Can be fully tested by seeding the data store with vocabulary entries older than 7 days that have no "retained" mark, then verifying they appear in the separate old words section and are absent from the current date groups.

**Acceptance Scenarios**:

1. **Given** vocabulary entries exist that are older than 7 days and not marked as retained, **When** the panel is displayed, **Then** those words appear in a dedicated "Old Unretained Words" section, separate from current date groups.
2. **Given** a word in the old unretained list is checked as retained, **When** the user marks it, **Then** it is removed from the old list and considered learned.
3. **Given** all words from a week-old session are retained, **When** the panel loads, **Then** the old unretained section is either empty or hidden.

---

### Edge Cases

- What happens when no vocabulary has been captured yet? The panel should display an empty state message rather than blank space.
- What happens when the translation service is unavailable during a retry? The user sees an error message and the retry button becomes available again.
- What happens when a very large number of words have been captured on a single date? The panel itself scrolls vertically; individual date groups do not have independent scroll containers.
- What happens when the 7-day threshold is crossed while the app is running? The word should move to the old unretained section on the next panel refresh or app launch.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The vocabulary panel MUST be displayed on the left side of the screen.
- **FR-002**: Vocabulary entries MUST be grouped by capture date, with the date displayed as a heading for each group.
- **FR-003**: Each date group MUST display a "Retry Translation" button adjacent to the date heading.
- **FR-004**: Each vocabulary entry within a date group MUST display the source word and its translation in a `word → translation` format.
- **FR-005**: Each vocabulary entry MUST include an "ok" checkbox that the user can toggle to mark the word as retained.
- **FR-006**: The retained state of each word MUST be persisted so it survives app restarts.
- **FR-007**: The panel MUST include a separate section listing vocabulary words that are older than 7 days and have not been marked as retained.
- **FR-008**: When the user clicks "Retry Translation" for a date group, the system MUST re-attempt translation for **all** entries in that group, replacing existing translations.
- **FR-009**: Words marked as retained MUST be excluded from the old unretained words section.
- **FR-010**: The panel MUST display an empty state message when no vocabulary entries exist.

### Key Entities *(include if feature involves data)*

- **VocabularyEntry**: Represents a single captured word, with its translation, capture date, and retained status.
- **DateGroup**: A logical grouping of vocabulary entries sharing the same capture date, used to organise panel display.
- **OldUnretainedList**: A derived view of vocabulary entries older than 7 days with retained status = false.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All vocabulary entries render and are scrollable within 1 second of the user opening the panel.
- **SC-002**: Users can mark a word as retained in under 2 taps/clicks, with the change reflected immediately in the UI.
- **SC-003**: The old unretained words section accurately displays all and only vocabulary entries older than 7 days with retained = false, with zero omissions or false inclusions.
- **SC-004**: Retry Translation completes and updates the visible translations within a time consistent with normal translation operations, and the button is re-enabled upon completion.
- **SC-005**: Retained state is preserved across app restarts with 100% fidelity (no data loss).

---

## Assumptions

- The application already has a mechanism for capturing vocabulary words from the clipboard and storing them with a timestamp (existing feature 001).
- "Left side of the screen" refers to a sidebar or panel anchored to the left edge of the main application window.
- The "7-day" threshold is calculated from the capture date of the word (not from a last-seen date).
- Words marked as retained are still visible in their original date group (just styled as checked) and do not disappear from current groups — only excluded from the old unretained section.
- The "Retry Translation" button applies to all untranslated or failed words in that specific date group; it does not retranslate already-translated, retained words by default.
- The panel is always visible (not a toggle/drawer), as the user described it as a persistent display.
- A single user context is assumed (no multi-user or sync considerations for this feature).
