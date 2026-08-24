# Contract Amendment: VocabularyListView Layout

**Feature**: 011-inbox-layout-fix  
**Amends**: `specs/006-vocabulary-sidebar/contracts/vocabulary-sidebar.md`  
**Date**: 2025-08-24

---

## Amendment: Remove Hard-coded Frame Constraints from VocabularyListView

### Context

`specs/006-vocabulary-sidebar/contracts/vocabulary-sidebar.md` (C-02) defines the panel as:
- **Width**: 340 pt
- **Height**: `visibleFrame.height`

The original implementation of `VocabularyListView` (Epic 1 prototype code) introduced two
frame modifiers that contradict C-02:

| Modifier | Value | Problem |
|----------|-------|---------|
| `.frame(width: 380)` on `List` | 380 pt | 40 pt wider than the 340 pt panel → overflow clips `SidebarTabBar` |
| `.frame(maxHeight: 500)` on `List` | 500 pt cap | Prevents list from filling `visibleFrame.height` → gap below list |
| `.frame(width: 380, height: 200)` on `EmptyStateView` | fixed | Pins empty state to 200 pt instead of centring in full height |

### New Contracts

The following contracts are added to the existing `vocabulary-sidebar.md` set:

| # | Contract |
|---|----------|
| C-24 | `VocabularyListView` MUST NOT apply a fixed or capped `height` frame to its `List`. The list MUST fill all available vertical space provided by `VocabularySidebarView`. |
| C-25 | `VocabularyListView` MUST NOT apply a fixed `width` frame to its `List` or empty-state view. Width MUST use `.infinity` and be constrained by the panel's 340 pt width (C-02). |
| C-26 | The empty-state placeholder MUST be centred in the full content area using `.frame(maxWidth: .infinity, maxHeight: .infinity)`. |

### No Changes to Existing Contracts

C-01 through C-23 are unchanged.
