# Quickstart: Translation Reliability — Validation Guide

**Branch**: `004-translation-reliability` | **Date**: 2025-07-18 (updated)
**Depends on**: `data-model.md`, `contracts/translation-service-v2.md`

---

## Prerequisites

- macOS 15+ for Apple Translation path; macOS 13–14 for LibreTranslate fallback path
- `swift build` completes without errors
- App runs from `.build/debug/ClipboardVocab` or a built binary
- For the Apple Translation path: on first run, macOS will prompt to download the EN→FR language pack if not already installed

---

## Setup

```bash
# Build from project root
swift build

# Run the app (or open the built binary)
.build/debug/ClipboardVocab
```

The app appears as a clipboard icon in the macOS menu bar. **Do not open the vocabulary panel yet.**

---

## Scenario 1 — Words captured before opening the panel get translated (FR-001, FR-002, FR-003, SC-001)

**Goal**: Verify that entries captured before the first popover open are automatically translated once the Apple Translation session is ready — without any user action beyond launching the app.

**What this tests**: Bug 1 fix — the `.translationTask` callback fires once, sets the session, calls `retryPendingTranslations()`, and stops (no infinite loop).

**Steps**:

1. Launch the app. Confirm the menu bar icon appears.
2. **Without opening the panel**, copy the following words one at a time (wait ~1 second between each):
   - `threshold`
   - `resilience`
   - `ephemeral`
3. Wait 5–10 seconds for the translation session to initialise and translations to complete in the background.
4. Click the menu bar icon to open the vocabulary panel.

**Expected outcome**:

All three rows display French translations with no orange "pending" badge:
- `threshold → seuil`
- `resilience → résilience`
- `ephemeral → éphémère`

Row updates happen in-place via GRDB `ValueObservation` — no panel close/reopen needed.

**Failure indicator**:
- Any row still shows "pending translation" after 15 seconds → Bug 1 not fixed (loop may still be re-triggering or session not ready).
- CPU usage stays elevated indefinitely after launch → `invalidate()` loop still present.

---

## Scenario 2 — Retry spinner terminates correctly (FR-004, SC-002)

**Goal**: Verify the "Réessayer la traduction" button spinner appears, shows progress, and stops when the retry operation is complete.

**What this tests**: Bug 2 fix — the spinner state is stable across GRDB `ValueObservation`-driven re-renders.

**Setup**: Force some entries to remain pending. Either:
- Run on macOS 13–14 (Apple session unavailable), or
- Set `service.libreTranslateURL = URL(string: "http://127.0.0.1:1")!` in a debug build to make the fallback unreachable before capturing words, then restore a valid URL before tapping retry.

**Steps**:

1. Capture 3 words while translations are unavailable — they appear with orange pending badges.
2. Restore a valid translation endpoint (or re-enable Apple session).
3. Open the vocabulary panel and locate the date group with pending entries.
4. Tap the **"Réessayer la traduction"** button.

**Expected outcome**:

1. The button is immediately replaced by a `ProgressView` spinner.
2. Rows update one by one as each translation completes.
3. When all entries in the group are translated, the spinner disappears. The retry button also disappears (since no pending entries remain in the group).
4. If new words are captured mid-retry (causing a `ValueObservation` re-render), **the spinner stays visible** until the retry task finishes.

**Failure indicator**:
- Spinner disappears before translations are complete → Bug 2 not fixed (`@State isRetrying` still resetting on re-render).
- Spinner persists indefinitely after translations are complete → task not completing or state not being written back.

---

## Scenario 3 — Manual retry uses fresh pending entries, not a stale snapshot (FR-005, SC-003)

**Goal**: Verify that tapping retry does not waste API calls on already-translated entries.

**What this tests**: Bug 3 fix — `retryPendingTranslations()` is called instead of passing `group.entries`.

**Steps**:

1. Capture 3 words while translations are unavailable (3 pending entries).
2. Wait for the background `NWPathMonitor` retry to translate 1 or 2 of them automatically (or manually mark one as translated in the DB for testing).
3. Open the panel and tap the retry button for the group.

**Expected outcome**:

Only the genuinely pending entries are translated. No duplicate translation calls are made for already-translated entries. The spinner stops promptly (not running extra API calls).

**Observable check**: If you have network logging enabled (e.g., Charles Proxy or `CFNETWORK_DIAGNOSTICS=1`), you should see exactly N HTTP/Apple Translation requests, where N = number of still-pending entries at tap time.

---

## Scenario 4 — Fallback misconfigured: entries stay pending, no crash (FR-007)

**Goal**: Verify that a broken fallback URL leaves entries pending without corrupting data or crashing.

**Steps**:

1. Force macOS 13/14 code path (or run on older OS / set `appleSession = nil` via debugger).
2. Set `libreTranslateURL` to `http://127.0.0.1:1/translate`.
3. Copy 2 words.

**Expected outcome**:

- Both entries appear in the panel with "pending translation" badges.
- The app does not crash.
- No error is shown to the user (silent failure as per FR-007).
- When a valid translation endpoint is later configured and the connectivity monitor fires, the entries are translated.

---

## Run Unit Tests

```bash
# Run translation service tests (covers retryPendingTranslations, retryGroup, translate contracts)
swift test --filter TranslationService

# Run all tests
swift test
```

All tests must pass (green). Tests use in-memory DB (`Database(path: ":memory:")`) and an unreachable URL (`http://127.0.0.1:1`) to avoid real network calls.

---

## References

- Data model: [`data-model.md`](data-model.md)
- Updated contract: [`contracts/translation-service-v2.md`](contracts/translation-service-v2.md)
- Feature spec: [`spec.md`](spec.md)
- Research decisions: [`research.md`](research.md)
- Prior translation contract: [`specs/003-automated-clipboard-translation/contracts/translation-service.md`](../003-automated-clipboard-translation/contracts/translation-service.md)
