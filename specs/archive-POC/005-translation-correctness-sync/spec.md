# Feature Specification: Translation Correctness & Sync

**Feature Branch**: `005-translation-correctness-sync`

**Created**: 2025-07-18

**Status**: Draft

**Input**: User description: "i want the translation work well in the project configuration, without any bug or problem or sync"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Every captured word is translated reliably, with no entry ever stuck as "pending" (Priority: P1)

A user copies English words throughout the day. When they open the vocabulary panel — whether moments after copying or hours later — every eligible entry shows its French translation. No entry is permanently stuck in "pending translation" state.

**Why this priority**: This is the core end-to-end promise of the app. A word that never gets translated is a word that provides zero learning value. All other stories build on this guarantee.

**Independent Test**: Copy five distinct English words across separate sessions, varying the time before opening the panel. Each word must appear in the vocabulary panel with a French translation — no entry may remain in "pending" state indefinitely once the translation backend is reachable. Delivers the full value proposition independently.

**Acceptance Scenarios**:

1. **Given** the app has just launched and the translation backend becomes ready, **When** there are pending entries in the store, **Then** all pending entries are translated automatically within 10 seconds, without any user action.
2. **Given** a word is copied while the vocabulary panel is closed, **When** the translation backend is available, **Then** the word appears with its French translation the next time the panel is opened — no pending state is visible.
3. **Given** a word is copied while the vocabulary panel is open, **When** the translation backend is available, **Then** the French translation appears in the row within 5 seconds, without requiring a manual refresh.
4. **Given** all entries are already translated, **When** the translation backend triggers its session callback again (e.g., after a model check), **Then** no redundant translation work is performed and no entry is re-submitted for translation unnecessarily.

---

### User Story 2 — The vocabulary panel always reflects the current translation state without requiring manual actions (Priority: P1)

A user opens the vocabulary panel and immediately sees the correct translation status for every entry. Translations that complete in the background appear automatically in the panel — the user never needs to close and reopen the panel to see an update.

**Why this priority**: Stale data in the UI undermines trust. If translations complete silently but the panel still shows "pending", the user cannot tell whether the app is working. This story preserves the silent, non-interruptive promise while still keeping the UI truthful.

**Independent Test**: Open the panel with one or more pending entries visible. Without closing the panel, wait for the background translation to complete. The pending badge must replace itself with the French translation automatically, within 5 seconds of the DB write — no tap, swipe, or panel close-and-reopen required.

**Acceptance Scenarios**:

1. **Given** the vocabulary panel is open and showing a pending entry, **When** the translation for that entry completes in the background, **Then** the French translation appears in the row automatically within 5 seconds.
2. **Given** the vocabulary panel is open, **When** a new word is captured from the clipboard and immediately translated, **Then** the new entry with its French translation appears in the list automatically.
3. **Given** the panel is reopened after a period of background capture, **When** it renders, **Then** the displayed data matches the current state of the local store with no lag or partial render.

---

### User Story 3 — Manual retry works correctly and terminates, even during concurrent background activity (Priority: P2)

A user sees pending entries in the vocabulary panel and taps the "Réessayer la traduction" button for a date group. A progress indicator appears immediately, the translations complete, and the indicator disappears. The retry does not loop, does not show stale state, and does not interfere with background translation that may be running simultaneously.

**Why this priority**: The retry button is the user's only explicit control over translation. Correctness here is required to avoid eroding trust, but it is P2 because background translation (P1) makes manual retry less frequently needed.

**Independent Test**: With three pending entries in a group, tap the retry button while simultaneously triggering a background translation (e.g., by copying a new word). The spinner must appear and then stop cleanly. No entry must be shown as pending once the retry completes successfully, and the spinner must not persist after all entries are translated.

**Acceptance Scenarios**:

1. **Given** a date group contains pending entries, **When** the user taps the retry button, **Then** a progress indicator replaces the button immediately.
2. **Given** the retry operation completes successfully, **When** all pending entries in the group are translated, **Then** the progress indicator disappears and the retry button is no longer shown (no pending entries remain).
3. **Given** a retry is in progress and a new word is captured (triggering a list re-render), **When** the re-render occurs, **Then** the spinner remains visible for the full duration of the retry task and does not reset.
4. **Given** the translation backend is unreachable during a manual retry, **When** the retry fails for all entries, **Then** the progress indicator stops, an error message is shown, and the retry button becomes available again.

---

### Edge Cases

- What happens if the translation backend becomes unavailable mid-retry? → Entries that completed before the failure are saved as translated; remaining entries stay pending. The spinner stops and an error is shown; the retry button is available again.
- What happens if the app is quit and relaunched while entries are pending? → On next launch, the translation backend initialises and automatically translates all pending entries, as in User Story 1 Scenario 1.
- What happens if the same word is copied multiple times in rapid succession while translation is in flight? → Deduplication ensures only one entry exists; the seen-count increments. The translation result is written once.
- What happens if the translation backend is available but returns an empty or malformed result? → The entry stays pending and the error is not surfaced to the user; it will be retried on the next connectivity event or manual retry.
- What happens if both the on-device translation model (macOS 15+) and the network fallback are simultaneously unavailable? → Entries remain pending with no loop or crash; translation is retried when either path becomes available again.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The translation backend session MUST be initialised once at application launch, independently of whether the vocabulary panel has been opened.
- **FR-002**: When the translation session becomes ready, the system MUST automatically translate all entries stored with "pending" status — exactly once per session-ready event, with no repeated re-translation of already-translated entries.
- **FR-003**: When the device regains network connectivity, the system MUST automatically retry all pending entries — exactly once per connectivity-restored event.
- **FR-004**: When a new word is captured and saved, the system MUST immediately attempt translation; if the backend is unavailable, the entry MUST remain as "pending" and be retried automatically later.
- **FR-005**: The vocabulary panel list MUST update automatically whenever a translation completes in the background, without any user action, using the live GRDB `ValueObservation` mechanism exclusively.
- **FR-006**: The manual retry operation for a date group MUST read the current pending status of entries from the data store at execution time — not from a stale closure-captured or render-time snapshot.
- **FR-007**: The retry progress indicator MUST remain visible for the full duration of the retry operation, regardless of any intermediate view re-renders caused by background data changes.
- **FR-008**: When the retry operation completes (successfully or with an error), the progress indicator MUST stop and the UI MUST reflect the final translation state of the entries.
- **FR-009**: The system MUST NOT produce more than one concurrent automatic retry for the same set of pending entries; if a retry is already in flight, a new trigger MUST NOT start a duplicate retry.
- **FR-010**: The "pending translation" indicator for an entry MUST be replaced by the French translation text as soon as the translation result is committed to the local store — no additional user interaction required.

### Key Entities

- **VocabularyEntry**: `translationStatus` (pending / translated), `frenchTranslation`, `englishText`, `firstCapturedAt`. Its persistence in the local store is the single source of truth for translation state.
- **TranslationSession**: On-device Apple model (macOS 15+) or network-based LibreTranslate fallback. Lifecycle is managed by the persistent session host. Its readiness triggers the initial automatic retry.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of pending entries are translated within 10 seconds of the translation backend becoming ready, with no user action required.
- **SC-002**: A word copied while the vocabulary panel is closed appears with its French translation on the first panel open, provided the backend was available at the time of capture.
- **SC-003**: A word copied while the vocabulary panel is open appears with its French translation within 5 seconds, automatically, without closing and reopening the panel.
- **SC-004**: The retry spinner for a date group stops within 2 seconds of the last translation in that group completing or failing.
- **SC-005**: No translation session callback loop or connectivity-triggered retry loop produces more than one translation attempt per pending entry per trigger event.
- **SC-006**: The app captures words and updates translation state while consuming less than 1% CPU at idle and less than 50 MB of RAM — translation correctness must not be achieved at the cost of background resource consumption.

## Assumptions

- The target user is a French speaker learning English on macOS 13 Ventura or later.
- The translation direction is exclusively English → French; other language pairs are out of scope.
- On macOS 15+, the on-device Apple Translation framework is the primary backend; LibreTranslate running locally on Docker (port 5001) is the fallback for macOS 13–14.
- Translation is performed sequentially for the current volume of pending entries (up to ~100); parallel translation is a future optimisation and out of scope.
- "Works well" means entries are never permanently stuck as pending when a translation backend is reachable — it does not imply zero-latency or guaranteed translation when both backends are unavailable.
- GRDB `ValueObservation` is the exclusive mechanism for live UI updates; no additional notification or pub-sub infrastructure will be introduced.
- No new SPM dependencies or schema migrations are required to achieve the described correctness guarantees; the existing service pipeline is structurally sound.
- The three bugs identified in `specs/004-translation-reliability` (infinite session loop, unstable retry spinner, stale entry snapshot) have been resolved; this spec governs the resulting stable, correct behaviour and adds any remaining gaps.
