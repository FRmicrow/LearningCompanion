# Quickstart: Inbox — Capture & Triage

**Feature**: 007-inbox-capture-triage  
**Date**: 2025-07-21

---

## Purpose

This guide provides runnable validation scenarios to verify that the Inbox feature works correctly end-to-end after implementation. It is **not** a code guide — see [`contracts/inbox-view.md`](contracts/inbox-view.md) for interface contracts and [`data-model.md`](data-model.md) for entity definitions.

---

## Prerequisites

- macOS 13+
- `swift build` available
- App built and running (menu bar icon visible)
- Self-hosted LibreTranslate on `http://localhost:5001` (optional — Inbox still works when translation is pending)

---

## Build

```bash
swift build
```

Expected: zero errors, zero warnings related to this feature.

---

## Test

```bash
swift test
```

Expected: all tests pass, including new tests for `VocabularyEntryRepository` triage methods and migration `v3`.

---

## Validation Scenarios

### Scenario 1 — New captured word appears in the Inbox

1. Launch the app (menu bar icon visible).
2. Open the sidebar (⌘⇧C or menu-bar left-click).
3. Navigate to the **Inbox** tab.
4. Copy an English word to the clipboard (e.g. "ephemeral").

**Expected**:
- Within ~1 second, "ephemeral" appears as a card in the Inbox list.
- The translation area shows a "Tap to reveal" placeholder or the Reveal button — the translation is hidden.
- The card shows the English word prominently with a headline font.

---

### Scenario 2 — Reveal translation

1. Have at least one word in the Inbox (see Scenario 1).
2. Click the **Reveal** button on the card, or press `Space`.

**Expected**:
- If translation is available: `"→ <translation>"` is shown below the word.
- If translation is still pending: a "Translation pending…" indicator is shown.
- No other card's translation is revealed.

---

### Scenario 3 — Save a word

1. Have at least one word in the Inbox.
2. Click the **Save** button on any card.

**Expected**:
- The card disappears from the Inbox immediately.
- The word is now in the vocabulary list (its `triageStatus` is `saved`).
- If other entries remain in the Inbox, the next card is shown.
- If the Inbox is now empty, the Inbox empty state is displayed.

---

### Scenario 4 — Ignore a word

1. Have at least one word in the Inbox.
2. Click the **Ignore** button on any card.

**Expected**:
- The card disappears from the Inbox immediately.
- The word does **not** appear in the vocabulary learning list.
- If the Inbox is now empty, the empty state is displayed.

---

### Scenario 5 — Empty state

1. Triage all words in the Inbox (save or ignore all).

**Expected**:
- The Inbox view displays the empty state (e.g. "No new words" or equivalent).
- No residual cards are visible.

---

### Scenario 6 — Swipe left to delete

1. Have at least two words in the Inbox.
2. On one card, swipe left (trackpad: two-finger swipe left).

**Expected**:
- A red **Delete** button is revealed on the right side of the card.
- Tapping Delete removes the card from the Inbox (entry is `ignored`).
- The other cards are unaffected.

---

### Scenario 7 — Swipe right to mark Known

1. Have at least two words in the Inbox.
2. On one card, swipe right (trackpad: two-finger swipe right).

**Expected**:
- A green **Known** button is revealed on the left side of the card.
- Tapping Known removes the card from the Inbox (entry is `known`).
- The other cards are unaffected.

---

### Scenario 8 — Menu-bar badge with pending words

1. Close the sidebar.
2. Copy 3 English words in quick succession (while sidebar is closed).

**Expected**:
- The menu-bar icon develops a badge showing "3" (or the count of pending unreviewed words).
- Badge updates within ~1 second of each capture.

---

### Scenario 9 — Badge clears when Inbox is emptied

1. Open the sidebar and triage all Inbox entries (save or ignore).
2. Close the sidebar.

**Expected**:
- The menu-bar icon badge is gone — no number is displayed.

---

### Scenario 10 — Live update while Inbox is open

1. Open the sidebar with the Inbox tab visible.
2. Copy a new English word.

**Expected**:
- The new word card appears in the Inbox list without any manual refresh.
- The list updates reactively within ~1 second.

---

### Scenario 11 — Keyboard triage (keyboard-only flow)

1. Open the sidebar and focus the panel (click inside it).
2. Copy a new word.
3. Press `Space` to reveal the translation of the top entry.
4. Press `Enter` to save it.

**Expected**:
- Space reveals the translation of the topmost card.
- Enter saves the topmost card — it disappears from the Inbox.
- The next card (if any) becomes the new top entry.
- No mouse interaction required throughout.

---

### Scenario 12 — Translation pending state

1. Stop the LibreTranslate Docker container (or disconnect from network if using remote).
2. Copy a new English word.
3. Open the Inbox and reveal the card's translation.

**Expected**:
- The Reveal action shows "Translation pending…" (not an empty string, not a crash).
- The Save and Ignore buttons are still available.
- When translation later succeeds, the card updates reactively.

---

### Scenario 13 — Duplicate capture deduplication

1. Copy the same English word three times.
2. Open the Inbox.

**Expected**:
- The word appears exactly **once** in the Inbox.
- Its `seenCount` reflects the number of times it was captured (visible in row metadata if shown).

---

### Performance Check — Badge update latency

1. Close the sidebar.
2. Copy a new word.
3. Measure time from clipboard copy to badge appearing on the menu-bar icon.

**Expected**: Badge appears within 1 second (SC-002).

---

## References

- Interface contracts: [`contracts/inbox-view.md`](contracts/inbox-view.md)
- Data model: [`data-model.md`](data-model.md)
- Feature spec: [`spec.md`](spec.md)
- Epic 1 reference: [`../006-vocabulary-sidebar/quickstart.md`](../006-vocabulary-sidebar/quickstart.md)
