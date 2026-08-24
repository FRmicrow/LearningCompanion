# Quickstart: Inbox Layout Fix

**Feature**: 011-inbox-layout-fix  
**Phase**: 1 — Manual validation  
**Date**: 2025-08-24

---

## Prerequisites

- macOS 13+ with the app built and running (`swift build && .build/debug/ClipboardVocab`)
- At least one vocabulary entry in the DB (copy any English word to trigger capture)
- Display at 1440×900 or higher

---

## Build

```bash
swift build
```

Expected: no new warnings or errors.

---

## Scenario 1 — Inbox list fills the panel height

1. Click the menu bar icon to open the sidebar panel.
2. Navigate to the **Inbox** tab (⌘1).
3. With ≥ 10 entries present, scroll the list.

**Expected**: The word list extends from the selection toolbar at the top to the tab bar
at the bottom. There is **no visible empty grey gap** between the last row and the tab bar.

**Fail condition**: A blank region appears below the last row before the tab bar is reached.

---

## Scenario 2 — Tab bar fully visible

1. Open the sidebar panel on any tab.
2. Look at the bottom of the panel.

**Expected**: All four tab bar buttons — **Inbox, Learn, Review, Statistics** — are fully
rendered with their icon and label visible. No button is clipped, obscured, or half-visible.

**Fail condition**: Any tab button label or icon is partially cut off.

---

## Scenario 3 — Empty-state placeholder centred

1. Delete all entries or test with a fresh in-memory DB.
2. Open the sidebar panel and navigate to the Inbox tab.

**Expected**: The empty-state message is centred in the full content area between the
selection toolbar and the tab bar.

**Fail condition**: The empty-state appears pinned to the top 200 pt of the content area
with blank space below.

---

## Scenario 4 — No regression on other tabs

1. After confirming Scenarios 1–3, switch through each tab: **Learn (⌘L), Review (⌘R), Stats (⌘4)**.

**Expected**: Each tab's content fills the full content area exactly as before. No layout
regressions introduced by the Inbox fix.

**Fail condition**: Any other tab shows unexpected layout breaks, clipping, or gaps.

---

## Reference

- Layout model: [data-model.md](data-model.md)
- Contract C-02: panel width = 340 pt, full `visibleFrame.height` — [vocabulary-sidebar.md](../../specs/006-vocabulary-sidebar/contracts/vocabulary-sidebar.md)
