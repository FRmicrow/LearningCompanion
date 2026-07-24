# Quickstart Validation Guide: Vocabulary Panel UI

**Branch**: `002-vocabulary-panel-ui` | **Date**: 2025-07-22
**References**: [data-model.md](data-model.md) · [contracts/vocabulary-panel-ui.md](contracts/vocabulary-panel-ui.md)

---

## Prerequisites

1. Xcode 15+ or `swift build` (Swift 5.9 toolchain).
2. macOS 13+.
3. Internet access (LibreTranslate fallback) **or** macOS 15 (Apple Translation framework).
4. A clean database or one migrated to v2 (migration runs automatically on first launch).

---

## Build & Run

```bash
# From repo root
swift build
.build/debug/ClipboardVocab
```

Or open in Xcode and run the `ClipboardVocab` scheme.

---

## Validation Scenario 1 — Date-grouped panel with "ok" checkbox (FR-001–006, SC-001–002)

**Setup**: Copy at least one English word to the clipboard while the app is running.

**Steps**:
1. Launch the app. The menu bar icon appears.
2. Click the menu bar icon to open the popover panel.
3. Observe the panel opens to the left of / below the icon.
4. Verify entries are grouped under a date heading (today's date).
5. Verify each entry shows `word → translation` (or pending badge).
6. Click the "ok" checkbox on one entry.
7. Verify the entry is visually styled as retained (e.g. strikethrough / muted).
8. Quit and relaunch the app.
9. Reopen the panel and verify the checkbox is still checked.

**Expected outcome**: Steps 3–9 all pass. Checkbox state survives restart.

---

## Validation Scenario 2 — Retry Translation button (FR-003, FR-008, SC-004)

**Setup**: Force a word into `.pending` state by temporarily making the translation service unreachable (e.g. disconnect from the internet before copying a word, or point `libreTranslateURL` to an invalid host in a debug build).

**Steps**:
1. Copy an English word while offline → entry appears with a "Pending" badge.
2. Reconnect to the internet (do NOT rely on automatic retry for this test).
3. Open the panel and locate the date group containing the pending entry.
4. Click "Réessayer la traduction" in the section header.
5. Observe a loading spinner next to the button; button becomes disabled.
6. Wait for the operation to complete (~1–5 seconds).
7. Verify the spinner disappears, the button re-enables, and the entry now shows a translation.

**Expected outcome**: Translation appears; spinner lifecycle is correct.

---

## Validation Scenario 3 — Old Unretained Words section (FR-007, FR-009, SC-003)

**Setup**: Insert a vocabulary entry with `firstCapturedAt` set to 8 days ago directly in SQLite:

```bash
# Path to DB (adjust username)
DB=~/Library/Application\ Support/ClipboardVocab/vocabulary.sqlite
sqlite3 "$DB" \
  "INSERT INTO vocabulary_entries \
     (englishText, frenchTranslation, translationStatus, seenCount, firstCapturedAt, lastSeenAt, isRetained) \
   VALUES \
     ('archaic', 'archaïque', 'translated', 1, \
      datetime('now', '-8 days'), datetime('now', '-8 days'), 0);"
```

> If the v2 migration has not run yet (column `isRetained` missing), launch the app once first to trigger it.

**Steps**:
1. Open the panel.
2. Verify "archaic → archaïque" appears in the **"Mots non retenus (>1 semaine)"** section at the bottom of the panel.
3. Verify "archaic" does **not** appear under today's date group.
4. Check the "ok" checkbox on "archaic" in the old words section.
5. Verify the entry is removed from the old words section.
6. Verify the old words section hides when empty (or shows an empty-state indicator).

**Expected outcome**: Entry appears in and is removed from the old section correctly.

---

## Validation Scenario 4 — Empty state (FR-010)

**Setup**: Use a fresh database (no entries).

**Steps**:
1. Delete or rename the existing `vocabulary.sqlite` file (app will create a new one on launch).
2. Launch the app and open the panel.
3. Verify neither date groups nor the old words section are shown.
4. Verify the empty-state placeholder message is displayed.

**Expected outcome**: Empty state view is shown with a descriptive message.

---

## Validation Scenario 5 — Unit tests (repository layer)

```bash
swift test --filter ClipboardVocabTests
```

**Tests to verify**:
- `testMarkRetained_persistsTrue`: Insert entry, call `markRetained(id:true)`, fetch and assert `isRetained == true`.
- `testMarkRetained_persistsFalse`: Mark retained, then call `markRetained(id:false)`, assert `isRetained == false`.
- `testFetchOldUnretained_excludesRetained`: Insert two old entries, retain one, assert only the unretained one is returned.
- `testFetchOldUnretained_excludesNewEntries`: Insert one old and one recent entry, assert only the old one is returned.
- `testDateGrouping_groupsByCalendarDay`: Insert entries on two different dates, assert grouping produces two groups with correct members.

---

## Known Limitations (v1 of this feature)

- The panel is a popover anchored to the menu bar icon, not a persistent sidebar window. "Left of screen" is achieved by the popover's preferred edge positioning.
- Retry Translation retranslates all entries in a group (including already-translated ones) as per spec scenario 2 of User Story 2.
- The 7-day threshold is recalculated at the time the `ValueObservation` fires; words are not moved in real-time while the app is running unless the DB changes.
