# Data Model: Inbox Layout Fix

**Feature**: 011-inbox-layout-fix  
**Phase**: 1 — Design  
**Date**: 2025-08-24

---

## Overview

This feature introduces **no new data entities, no schema migrations, and no repository
changes**. It is a pure SwiftUI layout correction.

This document records the layout model — the sizing relationships between the UI
components — because that is the "data" that was incorrectly specified in the source code.

---

## Layout Model (before → after)

### Panel Container

`VocabularySidebarPanel` sets the `NSPanel` frame at `show()` time:

```
width  = 340 pt  (VocabularySidebarPanel.width constant)
height = NSScreen.main?.visibleFrame.height  (full usable screen height)
```

This is **correct** and **unchanged**.

### VocabularySidebarView layout stack (VStack, spacing 0)

| Component | Height (before) | Height (after) | Width (before) | Width (after) |
|-----------|----------------|----------------|----------------|---------------|
| `DailyProgressBar` | intrinsic | intrinsic (unchanged) | fills parent | fills parent |
| `contentForTab(_:)` | `.infinity` | `.infinity` (unchanged) | `.infinity` | `.infinity` |
| `SidebarTabBar` | 56 pt fixed | 56 pt fixed (unchanged) | fills parent | fills parent |

The content area already uses `.frame(maxWidth: .infinity, maxHeight: .infinity)` in
`VocabularySidebarView`. The bug was that `VocabularyListView` **internally overrode**
this with narrower/shorter frames.

### VocabularyListView internal layout (the fix)

| Element | Before | After |
|---------|--------|-------|
| `EmptyStateView` frame | `width: 380, height: 200` | `maxWidth: .infinity, maxHeight: .infinity` |
| `List` width | `width: 380` | `maxWidth: .infinity` |
| `List` max height | `maxHeight: 500` | removed (no cap) |

### Overflow elimination

`width: 380 > panel width: 340` caused the `VStack` to overflow, pushing `SidebarTabBar`
40 pt to the right and partially below the visible panel frame. After the fix, all widths
use `.infinity` and are constrained naturally by the 340 pt panel.
