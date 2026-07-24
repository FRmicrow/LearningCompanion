# Quickstart: Automated Clipboard Translation

**Branch**: `003-automated-clipboard-translation` | **Date**: 2025-07-17
**Validates**: `spec.md` user stories US1, US2, US3 and success criteria SC-001 through SC-006

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| macOS | 13.0 Ventura or later |
| Swift toolchain | 5.9+ (`swift --version`) |
| Network access | Required for Scenarios 1 and 3; intentionally disabled for Scenario 2 |

### Build & Run

```bash
# From repository root
swift build
swift run ClipboardVocab
```

> On first launch macOS may prompt for **Accessibility permission** (required for the ⌘ Shift C global shortcut). Grant it in **System Settings → Privacy & Security → Accessibility**.

---

## Scenario 1 — Copy an English word while online (US1 / P1)

**Validates**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, SC-001, SC-006

**Prerequisites**: App running, capture active (default state), device online.

### Steps

1. Open any application (browser, text editor, Notes).
2. Copy the word `threshold` (Cmd+C).
3. Wait up to **3 seconds**.
4. Click the ClipboardVocab menu bar icon.

### Expected Outcome

- A new row appears in today's vocabulary group: `threshold → seuil`.
- `translationStatus` is `translated` (no "pending" badge).
- No second entry is created if `threshold` is copied again — the "seen count" increments.

### SC-001 Verification

Copy another word and note the elapsed time from copy to the entry appearing in the panel. Must be **≤ 3 seconds**.

---

## Scenario 2 — Copy while offline; translation auto-retries on reconnect (US2 / P2)

**Validates**: FR-005, FR-008, SC-004

**Prerequisites**: App running. **Disable network** (Wi-Fi off / Ethernet disconnected / Airplane mode on).

### Steps

1. With network **off**, copy the word `resilience`.
2. Click the menu bar icon immediately.
3. Verify the entry is present with a pending status (no French translation yet).
4. Re-enable network.
5. Wait up to **5 seconds**.
6. Click the menu bar icon again (or keep it open — GRDB ValueObservation auto-refreshes).

### Expected Outcome

- Step 3: entry `resilience` is visible, `frenchTranslation` is empty / shows "pending".
- Step 6: entry updates to `resilience → résilience` (or equivalent translation) within 5 seconds of reconnection.

### SC-004 Verification

Measure time from network re-enable to translation appearing. Must be **≤ 5 seconds**.

---

## Scenario 3 — Non-English and noise are silently discarded (US1 filters)

**Validates**: FR-002, FR-003, FR-004, SC-003

### Steps

Copy each of the following items and confirm **no entry appears** in the vocabulary panel:

| Text | Reason for discard |
|------|--------------------|
| `Bonjour monde` | Non-English (French) |
| `https://apple.com` | URL pattern |
| `/usr/local/bin/ruby` | Unix file path |
| `42.7` | Numeric-only |
| `This sentence is way too long and exceeds the fifty character maximum limit` | > 50 characters |

### Expected Outcome

None of the above texts create a vocabulary entry. The panel is unchanged after each copy.

---

## Scenario 4 — Pause and resume capture (US3 / P3)

**Validates**: FR-009, FR-010, FR-011

### Steps

1. Press **⌘ Shift C**. Observe the menu bar icon changes to the paused variant.
2. Copy the word `curious` from any app.
3. Open the panel — confirm `curious` does **not** appear.
4. Press **⌘ Shift C** again. Observe the icon reverts to the active variant.
5. Copy the word `curious` again.
6. Wait up to 3 seconds and open the panel.

### Expected Outcome

- Step 3: `curious` is absent from the vocabulary list.
- Step 6: `curious → curieux` (or equivalent) is present.
- Right-click the menu bar icon — the context menu shows "Pause Capture" when active and "Resume Capture" when paused.

---

## Scenario 5 — App restart resets pause state (US3 / FR-011)

**Validates**: FR-011

### Steps

1. Pause capture (⌘ Shift C or via menu).
2. Quit and relaunch the app.
3. Immediately copy the word `startup`.
4. Wait up to 3 seconds and open the panel.

### Expected Outcome

- `startup` appears with its French translation — the app started in active capture state.
- Menu bar icon shows the active (not paused) variant on launch.

---

## Scenario 6 — Idle CPU and memory (SC-005)

**Validates**: SC-005

### Steps

1. Launch the app. Do not copy anything for **10 minutes**.
2. Open Activity Monitor and filter for `ClipboardVocab`.

### Expected Outcome

- CPU usage: **< 1%** sustained.
- Memory: **< 50 MB**.

---

## Quick Reference: Compile-Time Constants

| Constant | Location | Default |
|----------|----------|---------|
| Polling interval | `ClipboardMonitorService` | 500 ms |
| Confidence threshold | `LanguageDetectionService.confidenceThreshold` | 0.6 |
| Length gate | `CaptureProcessorService` | 50 chars |
| Translation endpoint | `TranslationService.libreTranslateURL` | `libretranslate.com/translate` |

To point at a self-hosted LibreTranslate instance, set `TranslationService.libreTranslateURL` before the service is used (e.g., in `AppDelegate.applicationDidFinishLaunching`).

---

## Inspect the Database Directly

```bash
DB="$HOME/Library/Application Support/ClipboardVocab/vocabulary.sqlite"

# Most recent entries
sqlite3 "$DB" \
  "SELECT englishText, frenchTranslation, translationStatus, seenCount
   FROM vocabulary_entries ORDER BY firstCapturedAt DESC LIMIT 20;"

# Count pending translations
sqlite3 "$DB" \
  "SELECT COUNT(*) FROM vocabulary_entries WHERE translationStatus = 'pending';"
```
