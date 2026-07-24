# Quickstart: Vocabulary Sidebar — Native Panel

**Feature**: 006-vocabulary-sidebar  
**Date**: 2025-07-15

---

## Purpose

This guide provides runnable validation scenarios to verify that the sidebar panel works correctly end-to-end after implementation. It is **not** a code guide — see `contracts/vocabulary-sidebar.md` for interface contracts and `data-model.md` for entity definitions.

---

## Prerequisites

- macOS 13+
- Swift Package Manager available (`swift build`)
- Self-hosted LibreTranslate running on `http://localhost:5001` (or app launched without translation to test UI only)
- The app built and launched via `swift run ClipboardVocab` or by running the `.app` bundle

---

## Build

```bash
swift build
```

Expected: zero errors, zero warnings related to this feature.

---

## Validation Scenarios

### Scenario 1 — Panel opens from global hotkey

1. Launch the app (menu bar icon appears).
2. Focus any other application (e.g. Terminal, Safari).
3. Press **⌘⇧C**.

**Expected**:
- The vocabulary sidebar slides in anchored to the right edge of the screen.
- The sidebar spans the full usable screen height (below the menu bar).
- No title bar is visible on the panel.
- The previously focused application retains keyboard focus — typing in it still works.
- The Inbox tab is active by default.

---

### Scenario 2 — Panel opens from menu bar click

1. Launch the app.
2. Left-click the menu bar icon.

**Expected**: Same as Scenario 1 — sidebar appears, no focus stolen.

---

### Scenario 3 — Tab navigation via click

1. Open the sidebar (Scenario 1 or 2).
2. Click each of the four tab items in the bottom bar: **Inbox**, **Learn**, **Review**, **Stats**.

**Expected**:
- Each click immediately switches to the corresponding view.
- The active tab item is visually highlighted (filled icon / accent colour).
- Inactive tabs are visually dimmed.
- Learn, Review, and Stats may show placeholder/empty-state content in this epic (they are shells).

---

### Scenario 4 — Tab navigation via keyboard shortcuts

1. Open the sidebar and click anywhere inside it to focus it.
2. Press **⌘L**.
3. Press **⌘R**.
4. Press **⌘1**.
5. Press **⌘4**.

**Expected**:
- Each shortcut switches to the corresponding tab: Learn, Review, Inbox, Stats.
- No other application reacts to these shortcuts (they are panel-scoped).

---

### Scenario 5 — Daily progress bar

1. Launch the app with an empty or populated database.
2. Open the sidebar.

**Expected**:
- A progress bar is visible at the top of the panel.
- The label reads `"X / 20 words"` where X reflects the number of entries captured today.
- If X = 0, the bar is empty; if X ≥ 20, the bar is full.

3. Copy an English word to the clipboard (e.g. "ephemeral") while the sidebar is open.

**Expected**:
- Within ~1 second, the progress count increments by 1 without any manual refresh.

---

### Scenario 6 — Dismiss via Escape

1. Open the sidebar and confirm it is visible.
2. Click inside the panel to ensure it is key.
3. Press **Escape**.

**Expected**: The sidebar disappears. The previously active application retains focus.

---

### Scenario 7 — Dismiss via hotkey toggle

1. Open the sidebar (⌘⇧C).
2. Press **⌘⇧C** again without interacting with the sidebar.

**Expected**: The sidebar closes. The previously focused application is unaffected.

---

### Scenario 8 — Session memory (tab selection persisted within session)

1. Open the sidebar.
2. Click the **Stats** tab.
3. Press **⌘⇧C** to close the sidebar.
4. Press **⌘⇧C** to reopen it.

**Expected**: The Stats tab is still selected — the panel remembers the last active tab within the same app session.

---

### Scenario 9 — Panel floats above other windows

1. Open any application window (e.g. Safari, Finder).
2. Open the vocabulary sidebar.
3. Switch focus to the other application and bring its window to the foreground.

**Expected**: The vocabulary sidebar remains visible on top of the other application's window.

---

### Scenario 10 — Panel does not capture focus on show

1. Open a text editor (e.g. TextEdit) and type a few characters.
2. While actively typing, press **⌘⇧C** (global hotkey).
3. Continue typing.

**Expected**:
- The sidebar opens alongside the text editor.
- Typing continues in the text editor without interruption — the cursor has not moved to the sidebar.

---

## References

- Interface contracts: [`contracts/vocabulary-sidebar.md`](contracts/vocabulary-sidebar.md)
- Data model: [`data-model.md`](data-model.md)
- Feature spec: [`spec.md`](spec.md)
