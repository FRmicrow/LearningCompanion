# Vocabulary Sidebar — Native Panel

**Feature ID**: Epic 1  
**Status**: Draft  
**Created**: 2025-07-15  
**Feature Directory**: `specs/006-vocabulary-sidebar`

---

## Overview

Replace the existing floating popup window with an elegant, native macOS floating sidebar panel anchored to the right edge of the screen. The panel behaves as a persistent Learning Companion: it slides in when invoked, stays available without disrupting the user's workflow, and hosts multiple views (Inbox, Learn, Review, Stats) reachable via a bottom tab bar and global keyboard shortcuts.

---

## Problem Statement

The current vocabulary list is presented as a generic popup window. This framing makes the app feel like an afterthought rather than a first-class macOS tool. Users working in focused contexts — coding, reading, writing — find the popup jarring and visually inconsistent with macOS design conventions. The experience does not match the quality expected from apps like Raycast, CleanShot X, or Things 3, which use floating panels that feel native and unobtrusive.

---

## Goals

- Give the vocabulary tool a distinct, premium identity as a **Learning Companion** sidebar.
- Provide a panel that users can summon and dismiss without breaking their workflow.
- Enable multi-view navigation (Inbox / Learn / Review / Stats) from a single persistent surface.
- Surface daily learning progress at a glance.
- Allow all key actions to be performed with keyboard shortcuts alone.

---

## Non-Goals

- This epic does not implement the SRS engine or review session logic (deferred to Epic 3 & 4).
- This epic does not introduce new translation or clipboard capture behaviour.
- This epic does not add animations or Dark/Light mode polish (deferred to Epic 6).
- This epic does not implement onboarding screens.

---

## User Scenarios & Testing

### Scenario 1 — Opening the panel
**Given** the app is running in the menu bar  
**When** the user presses the global hotkey (or clicks the menu bar icon)  
**Then** the vocabulary sidebar slides in from the right edge of the screen, full-height, without a title bar, and does not steal window focus from the active application.

### Scenario 2 — Navigating between views
**Given** the sidebar is open  
**When** the user clicks one of the four tab items at the bottom (Inbox, Learn, Review, Stats)  
**Then** the corresponding view is shown immediately and the selected tab is visually highlighted.

### Scenario 3 — Keyboard navigation between views
**Given** the sidebar is open  
**When** the user presses ⌘L (Learn), ⌘R (Review), or the hotkey for Stats  
**Then** the sidebar switches to the matching view.

### Scenario 4 — Daily progress bar
**Given** the sidebar is open on any view  
**When** the user has completed some words for the day  
**Then** a "Today's Progress" bar at the top displays "X / 20" with a native progress indicator that reflects current progress.

### Scenario 5 — Dismissing the panel
**Given** the sidebar is open  
**When** the user presses Escape or the global hotkey again  
**Then** the sidebar is dismissed without disrupting the previously focused application.

### Scenario 6 — Panel above other windows
**Given** the user has other applications open  
**When** the sidebar is visible  
**Then** it floats above all other application windows without capturing or blocking their focus.

---

## Functional Requirements

### F-101 — Floating Sidebar Window
- The existing NSWindow popup is replaced by a floating panel anchored to the right edge of the primary display.
- The panel spans the full height of the screen (below the menu bar).
- The panel has no title bar.
- The panel floats above all application windows but does not capture keyboard focus from the active app unless the user explicitly interacts with it.
- The panel can be shown and hidden via a global hotkey (existing shortcut preserved).
- The panel must be dismissed by pressing Escape or re-triggering the global hotkey.

### F-102 — Multi-View Navigation
- A bottom tab bar provides four navigation items: **Inbox**, **Learn**, **Review**, **Stats**.
- Tapping or clicking any tab switches to the corresponding view.
- The active tab is visually distinguished from inactive tabs.
- The following keyboard shortcuts are supported while the panel is focused:
  - `⌘L` → Learn view
  - `⌘R` → Review view
  - `⌘1` → Inbox view
  - `⌘4` → Stats view
- The panel remembers the last active view across show/hide cycles within the same session.

### F-103 — Daily Progress Bar
- The top of the panel displays a "Today's Progress" section showing `X / 20 words`.
- Progress is represented by a native horizontal progress bar.
- The target of 20 words per day is the default; it does not need to be user-configurable in this epic.
- Progress count reflects vocabulary entries saved or reviewed today.

### F-104 — Global Keyboard Shortcuts
- While the panel is visible and focused, the following shortcuts are active:
  - `Space` → Reveal hidden translation
  - `Enter` → Mark current item as Known
  - `⌘R` → Mark current item as Review later
  - `⌘H` → Hide/toggle translation visibility
  - `⌘L` → Switch to Learn mode
- Shortcuts are scoped to the panel; they must not interfere with other applications when the panel is not focused.

---

## Success Criteria

1. The sidebar opens and closes within 100 ms of the global hotkey press as perceived by the user.
2. The active application retains keyboard focus when the sidebar is shown (the user can continue typing in their app).
3. Users can navigate to any of the four views without touching the mouse (keyboard-only flow works end to end).
4. The daily progress bar reflects accurate counts within the same launch session.
5. All four keyboard shortcuts (Space, Enter, ⌘R, ⌘H) trigger their corresponding actions reliably while the panel is focused.
6. The panel remains visible above all other application windows at all times while shown.

---

## Key Entities

| Entity | Description |
|--------|-------------|
| `VocabularySidebar` | The main floating panel window that replaces the current popup. |
| `SidebarTab` | Enum representing the four navigation destinations: Inbox, Learn, Review, Stats. |
| `DailyProgress` | Value representing today's word count and daily target for the progress bar. |

---

## Dependencies

- Existing `ClipboardMonitorService`, `VocabularyEntryRepository`, and `TranslationService` remain unchanged.
- This epic adds a new window/panel layer on top of the existing pipeline; no data model changes are required.
- Epic 2 (Inbox view content), Epic 3 (SRS), and Epic 4 (Learn/Review session logic) will populate the views introduced here.

---

## Assumptions

- The daily target of 20 words is a fixed default; user-configurable targets are out of scope for this epic.
- "Full height" means the usable screen height excluding the macOS menu bar.
- The sidebar is anchored to the **right** edge of the primary display only; multi-monitor support is out of scope.
- The panel width is a fixed value (approximately 320–360 pt); resizability is out of scope.
- The existing global hotkey defined in `GlobalShortcutManager` continues to be used to toggle the sidebar.
- Dark/Light mode appearance correctness is out of scope (Epic 6 covers polish).
