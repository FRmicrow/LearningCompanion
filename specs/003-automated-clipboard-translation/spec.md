# Feature Specification: Automated Clipboard Translation

**Feature Branch**: `003-automated-clipboard-translation`

**Created**: 2025-07-17

**Status**: Draft

**Input**: User description: "Mettre en place un système de traduction automatisé pour ce que l'on copie"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Silent Capture & Translation on Copy (Priority: P1)

A French-speaking user learning English copies any English word or short phrase from any application. Within half a second the app silently captures it, detects that it is English, translates it to French, and saves the result to the vocabulary list — with no notification or interruption to the user's work.

**Why this priority**: This is the core value proposition of the entire product. Without this story, no other feature has any data to work with.

**Independent Test**: Copy the word "threshold" from a browser, wait ≤ 500 ms, open the vocabulary panel — the entry `threshold → seuil` appears in today's group. Delivers the full end-to-end value on its own.

**Acceptance Scenarios**:

1. **Given** the app is running and capture is active, **When** the user copies an English word of ≤ 50 characters from any application, **Then** the word is saved to the vocabulary list with its French translation within 3 seconds.
2. **Given** an entry already exists for a word, **When** the user copies that word again, **Then** the seen-count increments and no duplicate entry is created.
3. **Given** the app is running, **When** the user copies text that is not English (e.g., French, Spanish), **Then** nothing is captured and the vocabulary list is unchanged.
4. **Given** the app is running, **When** the user copies a URL, number, file path, or text longer than 50 characters, **Then** nothing is captured.

---

### User Story 2 — Offline Resilience (Priority: P2)

The user works offline or the translation service is temporarily unavailable. The word is still captured immediately and stored with a "pending" status. When connectivity is restored, the translation is performed automatically without any action from the user.

**Why this priority**: Uninterrupted capture guarantees no vocabulary is lost due to transient network conditions. It supports the core story but is not required for the first demo.

**Independent Test**: Disable network access, copy "resilience", re-enable network — the entry appears as pending then updates to its French translation automatically.

**Acceptance Scenarios**:

1. **Given** the device is offline, **When** the user copies an eligible English word, **Then** the entry is saved immediately with status "pending translation".
2. **Given** one or more entries are pending translation, **When** network connectivity is restored, **Then** all pending entries are automatically translated without user action.
3. **Given** the translation service returns an error for a specific word, **When** connectivity is restored, **Then** translation is retried for that word.

---

### User Story 3 — Pause & Resume Capture (Priority: P3)

The user wants to temporarily stop capturing clipboard content (e.g., while handling sensitive data). They can pause capture with a keyboard shortcut or via the menu bar icon, and resume it equally easily. The app communicates its current state visually through the menu bar icon.

**Why this priority**: Privacy and user control. Useful in real workflows but not required for the initial vocabulary-building value.

**Independent Test**: Press ⌘ Shift C → menu bar icon changes to paused variant → copy an English word → nothing is captured → press ⌘ Shift C again → icon reverts → copy a word → entry appears.

**Acceptance Scenarios**:

1. **Given** capture is active, **When** the user presses ⌘ Shift C or uses the menu bar context menu, **Then** capture is paused and the menu bar icon reflects the paused state.
2. **Given** capture is paused, **When** the user copies any text, **Then** nothing is captured.
3. **Given** capture is paused, **When** the user presses ⌘ Shift C or uses the menu bar context menu, **Then** capture resumes and the icon reverts to the active state.
4. **Given** the app is relaunched after being paused, **When** it starts, **Then** capture is active by default (pause state is not persisted across restarts).

---

### Edge Cases

- What happens when the user copies an empty string or whitespace only? → Silently ignored; no entry created.
- What happens when the copied text is mixed language (e.g., "the café")? → Language detection determines the dominant language; if English confidence is below threshold, the text is ignored.
- What happens when the translation service returns an empty or malformed translation? → Entry remains in "pending" status; retry is attempted on next connectivity event.
- What happens when the device has been offline for a long period with many pending entries? → All pending entries are translated in order on reconnection; the UI reflects "pending" until each one resolves.
- What happens when the user copies the same text faster than the polling interval? → The poll detects one change; the deduplication path handles it without creating duplicates.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST monitor the clipboard continuously in the background and detect new text content within 500 ms of a copy action.
- **FR-002**: The system MUST discard copied text that exceeds 50 characters.
- **FR-003**: The system MUST discard copied text that is not natural language (URLs, numbers, file paths, code-like patterns).
- **FR-004**: The system MUST use on-device language detection to identify the dominant language of the copied text and only proceed if it is English with confidence ≥ 0.6.
- **FR-005**: The system MUST save each eligible captured word to a persistent local vocabulary store immediately, before translation completes.
- **FR-006**: The system MUST request an EN→FR translation for each newly captured entry and update the stored entry with the result upon success.
- **FR-007**: The system MUST increment a "seen count" and update "last seen" timestamp when a word that already exists in the vocabulary is copied again, without creating a duplicate entry.
- **FR-008**: The system MUST store entries with a "pending" status when the translation service is unavailable, and automatically retry translation when connectivity is restored.
- **FR-009**: The system MUST allow the user to pause and resume clipboard capture via a global keyboard shortcut (⌘ Shift C) and via the menu bar icon context menu.
- **FR-010**: The system MUST reflect the current capture state (active / paused) through a visible change in the menu bar icon.
- **FR-011**: Capture state MUST NOT be persisted across application restarts; the app always starts in the active state.
- **FR-012**: The system MUST run without a Dock icon, operating exclusively from the menu bar.

### Key Entities

- **VocabularyEntry**: Represents a single captured word or phrase. Key attributes: original English text, French translation, translation status (pending / translated), seen count, first captured date, last seen date.
- **CaptureState**: Represents whether clipboard monitoring is currently active or paused.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A copied English word appears in the vocabulary list within 3 seconds when the device is online.
- **SC-002**: 100% of clipboard copies are evaluated (none silently dropped by the monitor itself); filtering happens explicitly downstream.
- **SC-003**: Language detection correctly rejects non-English content in more than 95% of cases across a representative corpus of English and French text.
- **SC-004**: Pending entries are translated within 5 seconds of network connectivity being restored.
- **SC-005**: The app consumes less than 1% CPU at idle (capture active, no clipboard activity) over a 10-minute observation window.
- **SC-006**: No duplicate entries are created even when the same word is copied multiple times in rapid succession.

## Assumptions

- The target user is a French speaker learning English on macOS 13 Ventura or later.
- The translation direction is exclusively English → French; other language pairs are out of scope.
- Short phrases up to 50 characters are included; longer passages (paragraphs, code blocks) are out of scope.
- A publicly accessible or self-hosted translation service endpoint is available; the specific provider is a deployment detail, not a product requirement.
- The app requires no user account or cloud sync; all data is stored locally on the device.
- Pause state is intentionally not persisted across restarts — users prefer capture to resume automatically on relaunch.
- The global keyboard shortcut (⌘ Shift C) may require Accessibility permission on macOS; this is expected behaviour and documented in onboarding.
