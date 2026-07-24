# UI Contract: Vocabulary Panel — Grouped View

**Component**: `VocabularyListView` (v2) hosted in `NSPopover` via `NSHostingController`
**Extends**: `specs/001-clipboard-vocab-capture/contracts/vocabulary-list-ui.md`
**Source**: `spec.md` FR-001–FR-010, User Stories 1–3

---

## Panel Layout

The panel is the root SwiftUI view hosted in the existing `NSPopover`. It is divided into three vertical zones rendered top-to-bottom:

| Zone | Condition | Component |
|------|-----------|-----------|
| Date Groups | One or more vocabulary entries exist | `VocabularyDateGroupSection` (one per calendar day) |
| Old Unretained Words | One or more entries older than 7 days with `isRetained = false` | `OldUnretainedWordsSection` |
| Empty State | Zero vocabulary entries in total | `EmptyStateView` (unchanged from v1) |

When both date groups and old unretained words are present, they appear in the same scrollable `List`. Date groups render first (most-recent date at top), followed by the old unretained section at the bottom.

**Frame**: width ~380 pt, `maxHeight` 500 pt, vertically scrollable.

---

## Zone 1 — Date Group Section (`VocabularyDateGroupSection`)

### Section Header

Each calendar day with captured entries renders a section header row containing:

| Element | Content | Notes |
|---------|---------|-------|
| Date label | Formatted date string, e.g. "22 juillet 2025" | Locale-formatted, date-only |
| "Retry Translation" button | Label: "Réessayer la traduction" | Always present per group; disabled while a retry is in progress for that group |
| Loading indicator | Spinner (ProgressView) | Visible only while retry is in progress; replaces or accompanies button |

### Entry Rows (`VocabularyEntryRow` — updated)

Each entry within a date group renders:

| Element | Content | Condition |
|---------|---------|-----------|
| Source word | `englishText` | Always |
| Arrow + translation | `"→ frenchTranslation"` | `translationStatus == .translated` |
| "Pending" badge | Orange badge | `translationStatus == .pending` |
| "ok" checkbox (`Toggle`) | Checked = retained | Always; toggles `isRetained` |
| Retained style | Strikethrough or muted colour on source word | `isRetained == true` |
| Seen count | "Vu N fois" label | `seenCount > 1` |
| Delete action | Swipe-to-delete or trash button | Always |

> **Note**: The per-entry "Retry" link that existed in v1 is **removed**. Retry is now exclusively a per-group action at the section header level.

### Retry Button Behaviour

| State | Button | Indicator |
|-------|--------|-----------|
| Idle | Enabled, full opacity | None |
| In progress | Disabled, reduced opacity | `ProgressView` spinner shown |
| Complete | Returns to Idle | Spinner hidden |
| Error (service unavailable) | Returns to Idle | Error message shown inline under header |

---

## Zone 2 — Old Unretained Words Section (`OldUnretainedWordsSection`)

A dedicated section header labelled **"Mots non retenus (>1 semaine)"** followed by entry rows for all entries matching:

```
isRetained == false AND firstCapturedAt < (now − 7 days)
```

### Entry Row (same structure as Zone 1 rows)

The same `VocabularyEntryRow` component is reused. The "ok" checkbox is present and functional — marking a word as retained removes it from this section on the next observation update.

### Section Visibility

| Condition | Section |
|-----------|---------|
| No entries match filter | Section is hidden (not rendered) |
| One or more entries match | Section is visible |

---

## Zone 3 — Empty State

Unchanged from v1 contract. Displayed only when the total entry count is zero (no entries at all, including old ones).

---

## Interaction Summary

| User Action | Immediate Effect | Persisted? |
|-------------|-----------------|------------|
| Check "ok" on an entry | Entry visually marked retained; removed from Old section on next refresh | Yes — `isRetained = 1` in DB |
| Uncheck "ok" on an entry | Entry reverts to unretained styling | Yes — `isRetained = 0` in DB |
| Click "Réessayer la traduction" | All entries in the date group are retranslated; spinner shown during operation | Yes — `frenchTranslation` + `translationStatus` updated in DB |
| Delete an entry | Hard-deleted from DB; removed from all zones | Yes — row removed |

---

## Accessibility

- Section headers must have `accessibilityLabel` values (date string + "section").
- "Réessayer la traduction" button must have an `accessibilityLabel`.
- "ok" `Toggle` must have an `accessibilityLabel` of the form `"Mark [englishText] as retained"`.
- "Mots non retenus" section header must be a readable heading for VoiceOver.
- All behaviours from the v1 accessibility section remain in force.
