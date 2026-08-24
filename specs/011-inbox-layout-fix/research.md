# Research: Inbox Layout Fix

**Feature**: 011-inbox-layout-fix  
**Phase**: 0 — Root-cause analysis  
**Date**: 2025-08-24

---

## Root-Cause Analysis

### Finding 1 — Hard-coded `maxHeight: 500` caps the Inbox list

**Location**: [`VocabularyListView.swift` line 171](../../ClipboardVocab/UI/VocabularyListView.swift)

```swift
.frame(width: 380)
.frame(maxHeight: 500)
```

The `List` carrying vocabulary entries has both modifiers applied. `maxHeight: 500` is a
magic number chosen during early prototyping. The `VocabularySidebarPanel` already sizes
itself to the full `visibleFrame.height` (C-02 in `vocabulary-sidebar.md`), so SwiftUI's
layout system is prevented from propagating that height down to the list by this cap.

**Decision**: Remove `.frame(maxHeight: 500)`. The `VocabularyListView` is hosted inside
`VocabularySidebarView` with `.frame(maxWidth: .infinity, maxHeight: .infinity)`, which
already provides the correct flexible sizing. Removing the cap lets the list fill whatever
height the parent offers.

**Alternatives considered**:

| Alternative | Rejected Because |
|-------------|-----------------|
| Replace `500` with a computed value | Unnecessary — the parent already provides the correct height via `.infinity`; adding a computed value adds complexity with no gain. |
| Move the cap to `VocabularySidebarView` | The cap should not exist at any level; the panel itself is sized correctly at the `NSPanel` layer. |

---

### Finding 2 — Hard-coded `width: 380` overflows the 340 pt panel

**Location**: [`VocabularyListView.swift` line 170](../../ClipboardVocab/UI/VocabularyListView.swift)

```swift
.frame(width: 380)
```

The `NSPanel` width is fixed at **340 pt** (C-02, `vocabulary-sidebar.md`).
The `List` is told to be **380 pt** wide — 40 pt wider than its container.
SwiftUI clips the overflow, and because `VocabularySidebarView` uses a `VStack(spacing: 0)`,
the `SidebarTabBar` that follows the content area is pushed down and partially below the
panel's visible bounds.

**Decision**: Replace `.frame(width: 380)` with `.frame(maxWidth: .infinity)` on the `List`,
consistent with how other tab views (`LearnView`, `ReviewView`, `stats` placeholder) receive
their width from the parent.

**Alternatives considered**:

| Alternative | Rejected Because |
|-------------|-----------------|
| Change the panel width to 380 | Would require amending C-02 and break the 340 pt layout contract; wider panel may overlap menu bar or other UI. |
| Set `width: 340` (match panel) | Still a magic number; using `.infinity` is idiomatic SwiftUI and is already used by all other tabs. |

---

### Finding 3 — Empty-state placeholder frame

**Location**: [`VocabularyListView.swift` line 136](../../ClipboardVocab/UI/VocabularyListView.swift)

```swift
EmptyStateView()
    .frame(width: 380, height: 200)
```

Same dual problem: `width: 380` overflows, and `height: 200` pins the empty state to a
small region rather than centring it in the full available height.

**Decision**: Replace with `.frame(maxWidth: .infinity, maxHeight: .infinity)`. This centres
`EmptyStateView` in the full content area (between selection toolbar and tab bar), consistent
with how the stats placeholder is implemented.

---

## Summary of Changes Required

| File | Line | Change |
|------|------|--------|
| `ClipboardVocab/UI/VocabularyListView.swift` | 170–171 | `.frame(width: 380)` → `.frame(maxWidth: .infinity)`, remove `.frame(maxHeight: 500)` |
| `ClipboardVocab/UI/VocabularyListView.swift` | 136 | `.frame(width: 380, height: 200)` → `.frame(maxWidth: .infinity, maxHeight: .infinity)` |

**No other files need to change.** `VocabularySidebarPanel`, `VocabularySidebarView`, and
`SidebarTabBar` are already correct.
