# Feature Specification: Translation Reliability

**Feature Branch**: `004-translation-reliability`

**Created**: 2025-07-18

**Status**: Draft

**Input**: "Debug la traduction qui ne fonctionne pas et le bouton 'retry' qui tourne en boucle infinie. Analyse proprement le code et propose un plan d'action fiable."

---

## Context & Observed Problems

Code analysis of the current implementation reveals **three distinct, compounding bugs**. Each is described with its exact location and root cause.

---

### Bug 1 — Infinite loop in `TranslationSessionHost` (the primary cause of permanent "pending" entries)

**File**: `ClipboardVocab/UI/TranslationSessionHost.swift`, lines 77–84

**Root cause**: Inside `PersistentTranslationView`, the `.translationTask` callback unconditionally calls `configuration?.invalidate()` immediately after every session provision. Per Apple's API contract, calling `invalidate()` on the active configuration schedules a new invocation of the `.translationTask` callback. This creates a self-sustaining loop:

1. `.translationTask` fires → sets `appleSession`, calls `retryPendingTranslations()`, calls `configuration?.invalidate()`
2. `invalidate()` triggers the callback again → step 1 repeats indefinitely

In practice, `retryPendingTranslations()` is called repeatedly but the translations complete on the first or second pass and subsequent calls are no-ops. The real harm is that the session is re-assigned in a tight loop, which can cause in-flight translation requests to be cancelled when the session reference changes mid-request.

**The `invalidate()` call serves no purpose in its current position.** The original intent was to trigger a re-run after a model download completes, but calling it unconditionally negates that intent — a model download triggers the callback naturally without manual invalidation.

---

### Bug 2 — Retry spinner never stops (infinite spinner on the "Réessayer" button)

**File**: `ClipboardVocab/UI/VocabularyDateGroupSection.swift`, lines 85–95  
**Related**: `ClipboardVocab/UI/VocabularyListView.swift`, line 82

**Root cause**: The `.task(id: retryTrigger)` task calls `onRetryGroup()`, which is the closure `{ try await translationService.retryGroup(entries: group.entries) }` captured in `VocabularyListView`. The closure captures `group.entries` **at the time the section is constructed**, not at the time the task runs.

When a translation succeeds during the retry, GRDB's `ValueObservation` fires and causes `VocabularyListView` to re-render with updated `@State entries`. SwiftUI recreates the `VocabularyDateGroupSection` view struct with fresh props — but **the running `.task` holds a reference to the old closure** and continues executing against the stale entry snapshot.

There is a secondary problem: `retryTrigger` is a `@State` integer on the view struct. When SwiftUI destroys and re-creates the view (which it does on any parent list re-render), `retryTrigger` resets to `0` but `isRetrying` may also reset to `false` mid-task, leaving the spinner visible with no task backing it, or conversely leaving no spinner while a background task is still running.

**The net effect**: the spinner shows and may not stop, or the button remains incorrectly hidden/shown relative to the actual task state.

---

### Bug 3 — `retryGroup` operates on a stale entry snapshot

**File**: `ClipboardVocab/UI/VocabularyListView.swift`, line 82  
**Related**: `ClipboardVocab/Services/TranslationService.swift`, line 100

**Root cause**: `onRetryGroup` passes `group.entries` — a value derived from `@State entries` at render time — into `retryGroup(entries:)`. If the background `retryPendingTranslations()` (triggered by Bug 1's loop or by `NWPathMonitor`) has already translated some entries between the user tapping "Réessayer" and the task executing, those entries still appear as `.pending` in the snapshot. `retryGroup` internally re-filters for `.pending` status, so it will attempt to re-translate already-translated entries that happen to appear pending in the captured array.

While `retryGroup` is idempotent (re-translating an already-translated entry is harmless), the redundant HTTP/Apple Translation calls waste resources and can cause the spinner to run longer than necessary.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Words captured before opening the panel get translated (Priority: P1)

A user copies several English words throughout the day without ever opening the vocabulary panel. When they open the panel for the first time, all previously captured words appear with their French translations — none show "pending translation".

**Acceptance Scenarios**:

1. **Given** several words have been captured while the panel was closed, **When** the user opens the vocabulary panel for the first time, **Then** all captured entries display their French translation within 5 seconds.
2. **Given** the translation session initialises on app launch, **When** there are pending entries in the store, **Then** translation of those entries begins automatically without any user action.
3. **Given** a translation completes in the background, **When** the user opens the panel, **Then** the translated rows are already populated with no pending badge.

---

### User Story 2 — Manual retry button works reliably and stops when done (Priority: P1)

A user sees entries showing "pending translation". They press the "Réessayer la traduction" button for a date group. A progress indicator appears, translations complete, and the spinner disappears — it does not spin indefinitely.

**Acceptance Scenarios**:

1. **Given** a date group has pending entries, **When** the user taps the retry button, **Then** a progress indicator replaces the button.
2. **Given** all pending entries in the group are successfully translated, **When** the retry operation completes, **Then** the progress indicator disappears and the retry button is no longer shown (because no entries are pending).
3. **Given** the translation service is unreachable, **When** the retry operation completes, **Then** the progress indicator stops and an error message is shown; the retry button becomes available again.
4. **Given** a retry is in progress, **When** the app re-renders the list (e.g., a new word is captured), **Then** the in-progress retry is not interrupted and the spinner remains visible until the task finishes.

---

### User Story 3 — Connectivity-triggered automatic retry works without loops (Priority: P2)

When the device regains network connectivity after an offline period, all pending entries are retried once. The retry does not repeat in a tight loop.

**Acceptance Scenarios**:

1. **Given** entries are pending and the network is offline, **When** connectivity is restored, **Then** translation is automatically attempted for all pending entries.
2. **Given** all entries are translated, **When** connectivity changes again, **Then** no redundant translation attempts are made.

---

### Edge Cases

- What happens if the Apple Translation model is not yet downloaded? → The session callback fires after the download completes; entries remain pending in the meantime and are translated automatically once the session is ready.
- What happens if both the Apple session and the network are unavailable? → Words are captured and stored as pending; translation is deferred until either path becomes available, with no looping retry.
- What happens if a retry and a background auto-retry run concurrently? → `retryGroup` filters for `.pending` at execution time; translated entries are skipped. The last DB write wins; no data corruption occurs.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The translation session MUST be initialised once, at application startup, independently of the vocabulary panel visibility.
- **FR-002**: The `.translationTask` callback MUST NOT call `configuration?.invalidate()` unconditionally; it must be called only once, and only when a language model download has been detected as pending (i.e., the API signals that the model is not yet available).
- **FR-003**: When the translation session becomes ready for the first time, the system MUST automatically translate all entries currently stored with "pending" status — exactly once.
- **FR-004**: The retry button's task MUST be resilient to parent view re-renders; the spinner MUST remain visible for the full duration of the retry operation, regardless of SwiftUI view identity changes.
- **FR-005**: The retry operation MUST read the current pending status of entries from the data store at execution time, not from a stale closure-captured snapshot.
- **FR-006**: When the vocabulary panel opens and pending entries exist, the system MUST attempt to translate them if a translation session is available — this MUST NOT cause a loop if the panel is repeatedly opened and closed.
- **FR-007**: The fallback translation path (network-based) MUST leave entries as `.pending` and not throw an unhandled error when it is misconfigured or unreachable.
- **FR-008**: The "pending translation" visual indicator MUST disappear and be replaced by the French translation as soon as the translation result is saved to the database, without requiring any user interaction.

### Key Entities

- **VocabularyEntry**: `translationStatus` (pending / translated), `frenchTranslation`, `englishText`.
- **TranslationSession**: On-device Apple model (macOS 15+) or network-based fallback. Its lifecycle is managed by `TranslationSessionHost`.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After the translation session is ready, 100% of pending entries are translated within 10 seconds, with no user action required.
- **SC-002**: The retry spinner for a date group stops within 2 seconds of the last translation in that group completing.
- **SC-003**: No retry loop or session callback loop repeats more than once after all pending entries have been translated.
- **SC-004**: A word copied while the panel is open appears with its French translation in under 5 seconds under normal conditions, with no intermediate "pending" state visible beyond that window.

---

## Action Plan

The following changes are **ordered by dependency**. Each item maps directly to one or more bugs above.

### Fix 1 — Remove the unconditional `configuration?.invalidate()` call (targets Bug 1)

**File**: `ClipboardVocab/UI/TranslationSessionHost.swift`

Remove the call to `configuration?.invalidate()` inside the `.translationTask` callback. The callback already fires naturally when a session becomes available; calling `invalidate()` creates the infinite re-trigger described in Bug 1. If future behaviour requires re-triggering on model download completion, that should be driven by an explicit flag set by inspecting the session's availability, not by unconditionally invalidating on every callback.

```
// BEFORE (broken):
.translationTask(configuration) { session in
    service.appleSession = session
    await service.retryPendingTranslations()
    configuration?.invalidate()     // ← DELETE THIS LINE
}

// AFTER:
.translationTask(configuration) { session in
    service.appleSession = session
    await service.retryPendingTranslations()
}
```

### Fix 2 — Make the retry task stable across re-renders (targets Bug 2)

**File**: `ClipboardVocab/UI/VocabularyDateGroupSection.swift`

The root cause is that `.task(id: retryTrigger)` is attached to a view struct whose identity can change on parent re-renders. Replace the `retryTrigger` integer increment pattern with a **dedicated child view** (`RetryTaskRunner`) that owns its `@State isRetrying` and whose SwiftUI identity is stable. Alternatively, keep the current structure but ensure the task does not reset state mid-flight by using a stable `@StateObject` or by lifting retry state to the parent.

The minimal fix is:
- Replace `.task(id: retryTrigger)` with a plain `Task { }` launched from the button's action closure, storing a reference in a `@State var currentRetryTask: Task<Void, Never>?`.
- Cancel the previous task before starting a new one.
- Set `isRetrying = true` before the task starts and `isRetrying = false` in a continuation that is guaranteed to execute regardless of re-renders.

### Fix 3 — Read live pending entries from the repository at retry time (targets Bug 3)

**File**: `ClipboardVocab/UI/VocabularyListView.swift`

Change the `onRetryGroup` closure to fetch fresh pending entries from the repository rather than using the closed-over `group.entries` snapshot:

```swift
// BEFORE:
onRetryGroup: {
    return try await translationService.retryGroup(entries: group.entries)
}

// AFTER:
onRetryGroup: {
    return try await translationService.retryPendingTranslations()
    // or scope to the group's date range if per-group retry is required
}
```

If per-group retry is a UX requirement, the closure should accept the group's date range and call a new repository method `fetchPending(inGroup:)` at execution time, not at closure-capture time.

---

## Assumptions

- The primary translation engine on macOS 15+ is the Apple on-device model; the network fallback (LibreTranslate) is used on macOS 13–14 or when the Apple session is unavailable.
- The `NWPathMonitor`-based auto-retry in `AppDelegate` is correct and does not need changes; its trigger condition (connectivity restored) is appropriate.
- GRDB `ValueObservation` fires reliably on every DB write and drives all live UI updates; no additional notification infrastructure is required.
- Fix 2 is the highest-risk change from a SwiftUI lifecycle perspective and should be validated with a manual test session covering: rapid open/close of the panel, simultaneous background translation, and retry of a group with mixed pending/translated entries.
- Translating pending entries sequentially is acceptable for the current volume; parallel translation is a future optimisation and out of scope.
