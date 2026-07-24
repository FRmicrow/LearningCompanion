# Feature Specification: Clipboard Vocabulary Capture

**Feature Branch**: `001-clipboard-vocab-capture`

**Created**: 2025-07-18

**Status**: Draft

**Input**: User description: "Je veux que tu crée un addon pour mac qui tourne en tâche de fond - dans lequel dès que je copie quelque chose dans le presse papier, l'add on le récupère et en détecte le langage. Si c'est en français c'est ignoré. Si c'est de l'anglais, c'est noté dans l'add-on et traduit en français. Le but est de pouvoir récupérer au jour le jour une série de vocabulaire afin de l'apprendre."

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic English Word/Phrase Capture (Priority: P1)

While going about their day — reading articles, browsing documentation, or using any application — the user copies English text to their clipboard. Without any manual action, the addon silently captures the copied text, detects that it is English, translates it to French, and adds it to the vocabulary list.

**Why this priority**: This is the core value proposition of the product. Without automatic capture working silently in the background, no other feature has value.

**Independent Test**: Can be tested by copying an English word or phrase from any app on macOS and verifying it appears in the vocabulary list with its French translation, without any user interaction.

**Acceptance Scenarios**:

1. **Given** the addon is running in the background, **When** the user copies an English word (e.g. "threshold"), **Then** the word and its French translation (e.g. "seuil") are added to the vocabulary list automatically.
2. **Given** the addon is running in the background, **When** the user copies an English sentence or phrase, **Then** the full phrase and its French translation are added to the vocabulary list.
3. **Given** the addon is running in the background, **When** the user copies the same English word twice, **Then** the existing entry's "seen" counter is incremented and no new entry is created.

---

### User Story 2 - French Text Ignored (Priority: P1)

The user frequently copies French text (addresses, messages, notes). The addon must silently discard any clipboard content detected as French without adding it to the vocabulary list and without any notification or interruption.

**Why this priority**: Equal in importance to capture — incorrect vocabulary entries (French words filed as English) would break the learning experience and require manual cleanup.

**Independent Test**: Can be tested by copying a French sentence and confirming nothing is added to the vocabulary list.

**Acceptance Scenarios**:

1. **Given** the addon is running, **When** the user copies a French word or sentence, **Then** nothing is added to the vocabulary list.
2. **Given** the addon is running, **When** the user copies text in any language other than English (e.g. Spanish, German), **Then** nothing is added to the vocabulary list (non-English, non-French text is also ignored).
3. **Given** the addon is running, **When** the user copies a number, URL, or purely numeric/symbolic string, **Then** nothing is added to the vocabulary list.

---

### User Story 3 - Review Captured Vocabulary (Priority: P2)

The user wants to review all vocabulary captured since they started using the addon. They open the addon and see a chronological list of English entries with their French translations, so they can study what they have encountered.

**Why this priority**: Without a review interface, captured words are inaccessible and the learning goal cannot be achieved.

**Independent Test**: Can be tested by opening the addon UI after capturing several words, and verifying the list displays each entry with its English original and French translation.

**Acceptance Scenarios**:

1. **Given** vocabulary has been captured, **When** the user opens the addon, **Then** they see a list of entries each showing the original English text and its French translation.
2. **Given** the vocabulary list is open, **When** the user scrolls through entries, **Then** entries are ordered chronologically (most recent first or last — consistent ordering).
3. **Given** the vocabulary list contains entries, **When** the user looks at an entry, **Then** they can see both the original English text and the French translation clearly labelled.
4. **Given** an entry was captured while offline, **When** the user opens the addon, **Then** the entry is visible with a "translation pending" marker and an option to retry translation manually.
5. **Given** an entry is marked "translation pending", **When** connectivity is restored or the user triggers a retry, **Then** the French translation is fetched and the marker is replaced with the translation.

---

### User Story 5 - Pause and Resume Capture (Priority: P2)

The user is about to copy sensitive content (a password, a private message, financial data). They want to temporarily pause the addon so nothing is captured, then resume normal capture afterwards. They can do this instantly via a keyboard shortcut or the menu bar icon.

**Why this priority**: Without a pause mechanism, every clipboard copy — including sensitive data — passes through language detection and the translation service, creating a privacy risk in normal daily use.

**Independent Test**: Can be tested by activating the pause shortcut, copying an English word, verifying no entry is added, then resuming and confirming capture works again.

**Acceptance Scenarios**:

1. **Given** the addon is active, **When** the user presses the pause shortcut (default: Command+Shift+C) or clicks the menu bar toggle, **Then** capture is immediately paused and the menu bar icon changes to indicate the paused state.
2. **Given** capture is paused, **When** the user copies any text, **Then** nothing is added to the vocabulary list.
3. **Given** capture is paused, **When** the user presses the shortcut again or clicks the menu bar toggle, **Then** capture resumes and the icon returns to its active state.
4. **Given** the addon is paused and the user quits and restarts the addon, **Then** capture resumes in the active (unpaused) state by default.

---

### User Story 4 - Delete or Dismiss an Entry (Priority: P3)

The user reviews their vocabulary list and finds an entry that was captured by mistake (e.g. a code snippet, a product name, or irrelevant text). They want to remove it from the list.

**Why this priority**: Keeping the vocabulary list clean improves the quality of the learning experience over time.

**Independent Test**: Can be tested by deleting a specific entry and confirming it no longer appears in the list.

**Acceptance Scenarios**:

1. **Given** the vocabulary list is open, **When** the user deletes an entry, **Then** the entry is permanently removed from the list.
2. **Given** an entry has been deleted, **When** the same English text is copied again later, **Then** it is captured and added again (deletion does not create a permanent exclusion).

---

### Edge Cases

- What happens when the copied text is very long (e.g. an entire paragraph or article body)? → Silently skipped; only text ≤ 50 characters is captured (FR-014).
- How does the system handle mixed-language text (e.g. an English sentence with a French word inside)? → The dominant language is used. Given the 50-character cap, truly mixed-language chunks are rare; if the dominant language is not English, the text is discarded.
- What happens when the addon cannot detect language with sufficient confidence? → If language detection confidence falls below 0.6, the text is silently discarded (treated as non-English).
- What happens when the translation service is unavailable (no internet connection)? → The word is stored with a "translation pending" marker; translation is retried automatically when connectivity is restored, and the user can also trigger a manual retry from the vocabulary list (FR-015, FR-016, FR-017).
- What happens when the clipboard contains non-text content (an image, a file path)? → The addon only processes plain-text clipboard content (`NSPasteboardTypeString`); all other types (images, files, etc.) are silently ignored.
- What happens when the user has accumulated hundreds or thousands of entries? → SQLite handles this volume trivially; the vocabulary list uses virtual scrolling so only visible rows are rendered, with no performance degradation.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The addon MUST run persistently in the macOS background (system tray / menu bar) without requiring a visible foreground window.
- **FR-002**: The addon MUST monitor the system clipboard continuously and react whenever new text content is placed on it.
- **FR-003**: The addon MUST detect the language of clipboard text and determine whether it is English or not.
- **FR-004**: The addon MUST ignore clipboard content detected as French and take no action.
- **FR-005**: The addon MUST ignore clipboard content that is not English (any non-English language, including French, is ignored).
- **FR-006**: The addon MUST ignore clipboard content that contains no meaningful natural language (numbers only, URLs, file paths, code-only strings).
- **FR-014**: The addon MUST ignore clipboard content exceeding 50 characters; only words and short phrases (≤ 50 characters) are eligible for capture.
- **FR-007**: For English text, the addon MUST translate it to French.
- **FR-015**: If translation is unavailable at capture time, the addon MUST store the English entry with a visible "translation pending" marker instead of discarding it.
- **FR-016**: The addon MUST automatically retry pending translations when internet connectivity is restored.
- **FR-017**: The user MUST be able to manually trigger a translation retry for any entry marked "translation pending" from the vocabulary list.
- **FR-008**: The addon MUST store each captured English entry alongside its French translation in a persistent vocabulary list that survives application restarts.
- **FR-009**: The addon MUST prevent duplicate entries: if the same English text is captured more than once, the existing entry's "seen" counter is incremented and no new entry is created. The counter MUST be visible in the vocabulary list.
- **FR-010**: The addon MUST provide a way for the user to view their vocabulary list (e.g. clicking the menu bar icon opens a panel or window).
- **FR-011**: The vocabulary list MUST display each entry's original English text and its French translation.
- **FR-012**: The user MUST be able to delete individual entries from the vocabulary list.
- **FR-013**: The addon MUST operate silently — no system notifications or sounds are emitted on every capture event.
- **FR-018**: The addon MUST provide a pause/resume toggle accessible via both the menu bar icon and a global keyboard shortcut (default: Command+Shift+C).
- **FR-019**: When capture is paused, the menu bar icon MUST visually indicate the paused state (e.g. greyed out or badged).
- **FR-020**: The pause state MUST NOT persist across addon restarts; the addon always starts in the active (capturing) state.

### Key Entities

- **VocabularyEntry**: Represents a single captured item; attributes include original English text, French translation (nullable until resolved), translation status (translated / pending), date/time first captured, and a "seen" counter (integer ≥ 1, incremented on each subsequent capture of the same text).
- **VocabularyList**: The ordered collection of all VocabularyEntry records, persisted locally on the user's machine.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: English clipboard content is captured and translated within 3 seconds of the copy event, with no manual action from the user.
- **SC-002**: French and non-English clipboard content is discarded 100% of the time without producing any entry in the vocabulary list.
- **SC-003**: The addon consumes less than 1% CPU and less than 50 MB of RAM while running in the background, verifiable via macOS Activity Monitor during normal daily use.
- **SC-004**: The vocabulary list is accessible within 2 seconds of the user clicking the menu bar icon.
- **SC-005**: Vocabulary data is never lost across application restarts or macOS reboots.
- **SC-006**: Language detection accuracy for clearly English or clearly French text is above 95% in normal daily-use conditions.

---

## Assumptions

- The addon targets macOS only; other operating systems are out of scope.
- The user's primary source language is French and target learning language is English — the tool is designed for a French native speaker learning English.
- Non-English, non-French clipboard text (e.g. Spanish, German, code) is also ignored, not captured.
- The vocabulary list is stored locally on the user's device; no cloud sync or remote account is required for v1.
- An internet connection is required for translation. When unavailable, English entries are stored with a "translation pending" marker and retried automatically when connectivity is restored (FR-015, FR-016, FR-017). On-device offline translation is out of scope for v1.
- The addon is invoked and managed via the macOS menu bar (system tray icon), without a persistent Dock presence.
- Clipboard content exceeding 50 characters is silently skipped; the addon targets individual words and short phrases only. Longer text (sentences, paragraphs, articles) is out of scope.
- No export or spaced-repetition (flashcard) feature is in scope for v1; the goal is capture and review only.

## Clarifications

### Session 2025-07-18

- Q: When the same English text is captured more than once, should the entry be silently ignored, have a counter incremented, or be duplicated? → A: Keep one entry and increment a "seen N times" counter visible in the list (Option B).
- Q: What is the maximum text length eligible for capture? → A: Word/short phrase only, max 50 characters; anything longer is silently skipped (Option A).
- Q: What should happen when the translation service is unavailable at capture time? → A: Store the English word with a "translation pending" marker; auto-retry on reconnection; user can also manually retry from the vocabulary list.
- Q: Should there be a way to pause capture for privacy (e.g. when copying passwords)? → A: Yes — menu bar toggle plus a global keyboard shortcut (default: Command+Shift+C) to instantly pause/resume capture.
- Q: What are the concrete background resource usage limits for SC-003? → A: Less than 1% CPU at idle and less than 50 MB RAM (Option B).
