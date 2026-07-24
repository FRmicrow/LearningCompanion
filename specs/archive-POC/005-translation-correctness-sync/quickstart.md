# Quickstart: Translation Correctness & Sync — Validation Guide

**Branch**: `005-translation-correctness-sync` | **Date**: 2025-07-18
**Depends on**: `data-model.md`, `contracts/translation-service-v3.md`

---

## Prerequisites

- macOS 15+ for Apple Translation path; macOS 13–14 for LibreTranslate fallback path
- `swift build` completes without errors
- App runs from `.build/debug/ClipboardVocab` or a built binary
- For the Apple Translation path: on first run, macOS may prompt to download the EN→FR language pack if not already installed
- For the LibreTranslate fallback path: Docker running with `libretranslate/libretranslate` on port 5001 (`docker run -p 5001:5000 libretranslate/libretranslate`)

---

## Setup

```bash
# Build from project root
swift build

# Run all tests (must be green before proceeding)
swift test

# Run the app
.build/debug/ClipboardVocab
```

The app appears as a clipboard icon in the macOS menu bar.

---

## Scenario 1 — Words captured before opening the panel are translated automatically (FR-001, FR-002, FR-003, SC-001, SC-002)

**Goal**: Verify the end-to-end "capture while panel is closed → translate in background → translated on panel open" flow.

**Steps**:

1. Launch the app. **Do not open the vocabulary panel.**
2. Copy three English words one at a time (wait ~1 second between each):
   - `threshold`
   - `resilience`
   - `ephemeral`
3. Wait 10 seconds.
4. Open the vocabulary panel (click the menu bar icon).

**Expected outcome**:

All three rows display French translations with no pending badge:

- `threshold → seuil`
- `resilience → résilience`
- `ephemeral → éphémère`

**Failure indicators**:

- Any row shows "pending translation" after 15 seconds → session-ready retry path not working.
- CPU stays elevated after translations complete → concurrency guard not stopping re-triggers (SC-005).

---

## Scenario 2 — Live panel updates without close/reopen (FR-005, SC-003)

**Goal**: Verify that translations completing in the background appear in an already-open panel without any user action.

**Steps**:

1. Force pending entries: set `libreTranslateURL` to `http://127.0.0.1:1` in a debug build (or disable the Apple session), then capture 3 words.
2. Open the vocabulary panel. Confirm all 3 entries show "pending translation".
3. Re-enable the translation backend (restore a valid URL or re-enable Apple session).
4. **Do not close the panel.** Wait up to 10 seconds.

**Expected outcome**:

Each pending row updates in place to show its French translation, automatically, without closing and reopening the panel.

**Failure indicator**: Rows stay pending despite the backend being restored → GRDB `ValueObservation` not firing on translation writes, or `retryPendingTranslations()` not being called.

---

## Scenario 3 — Manual retry button works and spinner terminates (FR-006, FR-007, FR-008, SC-004)

**Goal**: Verify the retry spinner appears, stays visible throughout, and disappears cleanly.

**Setup**: Same as Scenario 2 — produce pending entries, then restore the backend.

**Steps**:

1. With pending entries visible in the panel, tap **"Réessayer la traduction"** for the date group.
2. While the spinner is visible, copy a new English word (this triggers a `ValueObservation` re-render).
3. Wait for translations to complete.

**Expected outcome**:

1. The button is immediately replaced by a `ProgressView` spinner.
2. Rows update one by one as each translation completes.
3. The spinner disappears within 2 seconds of the last translation completing.
4. Copying a new word mid-retry does NOT reset the spinner — it remains visible until the task finishes.

**Failure indicator**: Spinner disappears before translations complete → view re-render reset `@State isRetrying` prematurely (spec 004 Bug 2 regression).

---

## Scenario 4 — Concurrent retry triggers do not cause duplicate work (FR-009, SC-005)

**Goal**: Verify that when multiple retry triggers fire simultaneously (e.g., network restore + manual retry), only one pass through pending entries is executed.

**Steps** (requires network-level tooling such as Charles Proxy, `CFNETWORK_DIAGNOSTICS=1`, or a local HTTP mock):

1. Produce 3 pending entries.
2. Simultaneously: tap the retry button **and** trigger the connectivity monitor (e.g., toggle network off/on quickly).
3. Observe network requests.

**Expected outcome**:

Exactly 3 translation requests are made (one per pending entry). No entry is translated twice. The spinner stops cleanly.

**Observable proxy without network tooling**: All 3 entries are translated and the spinner stops within 5 seconds. CPU does not stay elevated after completion.

**Failure indicator**: More than 3 network requests observed (or 6, indicating double-pass) → `retryInProgress` guard not working.

---

## Scenario 5 — Fallback misconfigured: entries stay pending, no crash (FR-004)

**Goal**: Verify a broken fallback URL leaves entries pending without data corruption or crash.

**Steps**:

1. Set `libreTranslateURL` to `http://127.0.0.1:1` in a debug build (or run on macOS 13/14 without Docker).
2. Copy 2 words.

**Expected outcome**:

- Both entries appear with "pending translation" badges.
- The app does not crash.
- No error is shown to the user (silent failure).
- When a valid translation endpoint is later available and `retryPendingTranslations()` fires, both entries are translated.

---

## Run Unit Tests

```bash
# Run translation service tests (covers translate contract, retry contracts, concurrency guard)
swift test --filter TranslationService

# Run all tests (regression gate — must all pass)
swift test
```

All tests must pass. Tests use in-memory DB (`Database(path: ":memory:")`) and an unreachable URL (`http://127.0.0.1:1`) to avoid real network calls.

---

## References

- Data model: [`data-model.md`](data-model.md)
- Contract (v3): [`contracts/translation-service-v3.md`](contracts/translation-service-v3.md)
- Feature spec: [`spec.md`](spec.md)
- Research decisions: [`research.md`](research.md)
- Prior contracts:
  - v2: [`specs/004-translation-reliability/contracts/translation-service-v2.md`](../004-translation-reliability/contracts/translation-service-v2.md)
  - v1: [`specs/003-automated-clipboard-translation/contracts/translation-service.md`](../003-automated-clipboard-translation/contracts/translation-service.md)
