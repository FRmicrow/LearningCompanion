# Quickstart Validation Guide: Clipboard Vocabulary Capture

**Branch**: `001-clipboard-vocab-capture` | **Date**: 2025-07-18
**Purpose**: Prove the feature works end-to-end through runnable validation scenarios
**References**: [data-model.md](data-model.md) | [contracts/clipboard-monitor.md](contracts/clipboard-monitor.md) | [contracts/capture-processor.md](contracts/capture-processor.md) | [contracts/vocabulary-list-ui.md](contracts/vocabulary-list-ui.md)

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| macOS version | 13.0 (Ventura) or later |
| Xcode | 15.0+ |
| Swift | 5.9+ |
| Dependency manager | Swift Package Manager (SPM) |
| Dependencies | GRDB.swift, KeyboardShortcuts (resolved via SPM at build time) |
| Entitlements | `com.apple.security.app-sandbox` with `com.apple.security.network.client` (for translation) |
| Accessibility permission | Required for global keyboard shortcut; prompted on first launch |

---

## Build & Launch

```bash
# From repo root
xcodebuild -scheme ClipboardVocab -configuration Debug build
open build/Debug/ClipboardVocab.app
```

After launch:
- The menu bar icon appears in the system tray (top-right of screen).
- No Dock icon is shown.
- Capture is active by default.

---

## Validation Scenarios

### Scenario 1 — English word capture (Happy path)

**Goal**: Verify core capture pipeline works end-to-end (US1, FR-003, FR-007, FR-008)

1. Open any text editor or browser.
2. Copy the word `threshold` to clipboard (Cmd+C).
3. Wait up to 3 seconds.
4. Click the menu bar icon.

**Expected outcome**:
- The vocabulary panel opens.
- An entry for `threshold` is visible with `seuil` (or equivalent French translation) displayed.
- `seenCount` indicator is absent (first capture, count = 1, hidden per contract).
- Entry shows today's date.

---

### Scenario 2 — French text ignored (US2, FR-004)

1. Copy the French phrase `bonjour le monde` to clipboard.
2. Wait 3 seconds.
3. Open the vocabulary panel.

**Expected outcome**: No new entry appears. The list is unchanged from before the copy.

---

### Scenario 3 — Long text silently skipped (FR-014)

1. Copy any English text longer than 50 characters (e.g. a sentence from any article).
2. Wait 3 seconds.
3. Open the vocabulary panel.

**Expected outcome**: No new entry. List is unchanged.

---

### Scenario 4 — Deduplication and seen counter (FR-009, data-model.md deduplication rule)

1. Copy the word `serendipity`.
2. Wait 3 seconds. Confirm it appears in the list with no counter badge.
3. Copy `serendipity` again.
4. Wait 3 seconds. Open the panel.

**Expected outcome**:
- Still exactly one entry for `serendipity`.
- A "Seen 2 times" (or equivalent) counter badge is now visible on the entry.

---

### Scenario 5 — Pause and resume via keyboard shortcut (US5, FR-018, FR-019)

1. Press **Command+Shift+C**.

**Expected outcome**: Menu bar icon visually changes to indicate paused state.

2. Copy the English word `ephemeral`.
3. Wait 3 seconds. Open the panel.

**Expected outcome**: No entry for `ephemeral` — capture was paused.

4. Press **Command+Shift+C** again.

**Expected outcome**: Icon returns to active state.

5. Copy `ephemeral` again.
6. Wait 3 seconds. Open the panel.

**Expected outcome**: Entry for `ephemeral` now appears with its French translation.

---

### Scenario 6 — Pause state does not persist across restarts (FR-020)

1. Press Command+Shift+C to pause.
2. Quit the app (right-click menu bar icon → Quit, or Cmd+Q).
3. Relaunch the app.

**Expected outcome**: Icon is in active (not paused) state. Capture is immediately active.

---

### Scenario 7 — Translation pending + manual retry (FR-015, FR-016, FR-017)

1. Disconnect from the internet (turn off Wi-Fi or use system network settings).
2. Copy the English word `resilience`.
3. Wait 3 seconds. Open the panel.

**Expected outcome**:
- Entry for `resilience` is present.
- French translation field shows a "Translation pending" badge.
- A "Retry" action is visible on the entry.

4. Reconnect to the internet.

**Expected outcome**: Within a short time (background retry), the "Translation pending" badge is replaced with the French translation.

*Alternatively*: While still offline, tap the "Retry" button manually and confirm an error state or re-queued pending badge (translation remains pending until connectivity is restored).

---

### Scenario 8 — Delete an entry (US4, FR-012)

1. Ensure at least one entry exists in the vocabulary list (run Scenario 1 first if needed).
2. Delete the entry for `threshold` (swipe/button/right-click as implemented).
3. Verify the entry is gone from the list.
4. Copy `threshold` again.
5. Wait 3 seconds. Open the panel.

**Expected outcome**: Entry for `threshold` reappears with `seenCount = 1` — fresh entry, no memory of the deleted record.

---

### Scenario 9 — Non-text clipboard content ignored (FR-002, FR-006)

1. Copy an image (screenshot, photo from any app).
2. Wait 3 seconds. Open the panel.

**Expected outcome**: No new entry. List unchanged.

---

### Scenario 10 — Empty state (vocabulary-list-ui contract)

1. Delete all entries from the vocabulary list (or use a fresh install with no captures).
2. Open the panel.

**Expected outcome**: Panel displays an empty-state placeholder message in French (e.g. *"Copiez un mot anglais pour commencer."*). No entries, no errors.

---

### Scenario 11 — Performance validation (SC-003)

1. Leave the app running in the background for 10 minutes with normal computer use.
2. Open **Activity Monitor** (Applications → Utilities → Activity Monitor).
3. Find the `ClipboardVocab` process.

**Expected outcome**: CPU usage ≤ 1% at idle, Memory ≤ 50 MB.

---

### Scenario 12 — Data persistence across restarts (SC-005)

1. Capture several words (run Scenarios 1 and 4).
2. Quit the app.
3. Relaunch the app.
4. Open the panel.

**Expected outcome**: All previously captured entries are still present with their translations and seen counts intact.

---

## Database Inspection (optional, for debugging)

```bash
# Location of the SQLite database
DB_PATH="$HOME/Library/Application Support/ClipboardVocab/vocabulary.sqlite"

# Inspect all entries
sqlite3 "$DB_PATH" "SELECT id, englishText, frenchTranslation, translationStatus, seenCount, firstCapturedAt FROM vocabulary_entries ORDER BY firstCapturedAt DESC;"

# Check schema version
sqlite3 "$DB_PATH" "PRAGMA user_version;"
```
