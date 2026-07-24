# UI Contract: VocabularyListView (v1 — superseded)

> **⚠️ Deprecated**: This contract describes the v1 flat-list panel from `001-clipboard-vocab-capture`.
> It has been superseded by [`specs/002-vocabulary-panel-ui/contracts/vocabulary-panel-ui.md`](../../002-vocabulary-panel-ui/contracts/vocabulary-panel-ui.md).
> The per-entry "Retry" link described here has been removed; retry is now a per-date-group action.

**Component**: `VocabularyListView` (rendered inside `NSPopover` attached to `NSStatusItem`)
**Direction**: User-facing — defines what the vocabulary panel must show and how it must behave
**Source**: `spec.md` User Stories 3, 4, 5 + FR-010 to FR-013, FR-018/019

---

## Panel Trigger

| Action | Result |
|--------|--------|
| Click menu bar icon (active state) | Opens popover showing vocabulary list |
| Click menu bar icon (paused state) | Opens popover showing vocabulary list + paused banner |
| Click outside popover | Closes popover |
| Press Command+Shift+C (or user-remapped shortcut) | Toggles capture state (active ↔ paused); updates icon |

## Menu Bar Icon States

| State | Visual Indicator |
|-------|-----------------|
| Active, capturing | Standard icon (full opacity) |
| Paused | Greyed-out icon or badge/indicator (FR-019) |

## Vocabulary List Display

### Entry Row

Each row in the list MUST show:

| Element | Content | Condition |
|---------|---------|-----------|
| English text | Original captured word/phrase | Always |
| French translation | Translated text | `translationStatus == .translated` |
| "Translation pending" badge | Visual indicator | `translationStatus == .pending` |
| "Retry" action | Button/link to trigger manual retry | `translationStatus == .pending` |
| "Seen N times" indicator | Count label (hidden when `seenCount == 1`) | `seenCount > 1` |
| Captured date | Date of first capture | Always (may be compact, e.g. "Jul 18") |
| Delete action | Button/swipe/right-click to remove entry | Always |

### List Ordering

Entries ordered **most recent first** (descending `firstCapturedAt`). Sort order is fixed; no user-configurable sorting in v1.

### Empty State

When no entries have been captured yet, the panel MUST display a placeholder message explaining that copying English text will populate the list. The message must be in French (matching the user's language). Example: *"Copiez un mot anglais pour commencer."*

### Scroll Behaviour

List is vertically scrollable. Panel has a fixed maximum height; entries beyond the visible area are accessible by scrolling.

## Entry Deletion

| Action | Behaviour |
|--------|-----------|
| User confirms delete | Entry is hard-deleted from the database immediately |
| Same text copied again later | New entry created fresh with `seenCount = 1` (no memory of deletion) |
| Undo | Not in scope for v1 |

## Capture State Toggle (Pause/Resume)

| Trigger | Behaviour |
|---------|-----------|
| Command+Shift+C (global shortcut) | Toggles `CaptureState`; icon updates immediately |
| Menu bar icon click → pause/resume menu item | Same as shortcut |
| App restart | Always resets to `.active` regardless of state at quit (FR-020) |

## Accessibility

- All interactive elements (delete button, retry button) must have `accessibilityLabel` values.
- VoiceOver should be able to read each entry's English text, translation, and seen count.
