# Contract: Vocabulary Sidebar Panel

**Feature**: 006-vocabulary-sidebar  
**Date**: 2025-07-15  
**Type**: UI Contract (AppKit/SwiftUI window layer)

---

## Overview

This contract defines the public interface of `VocabularySidebarPanel` — the new floating panel window — and `VocabularySidebarView` — the SwiftUI root view it hosts. It also specifies how `StatusItemController` integrates with the panel and how `GlobalShortcutManager` is rewired.

---

## `VocabularySidebarPanel`

### Responsibility

Owns and manages the `NSPanel` lifecycle: creation, sizing, positioning, show, hide, and Escape-key dismissal. Does **not** own application-level state (capture toggle, quit).

### Interface

```swift
final class VocabularySidebarPanel {

    /// Show the panel, anchored to the right edge of the primary display.
    /// No-op if already visible.
    func show()

    /// Hide the panel.
    /// No-op if already hidden.
    func hide()

    /// Toggle visibility: show if hidden, hide if shown.
    func toggle()

    /// Whether the panel is currently visible.
    var isVisible: Bool { get }
}
```

### Behavioural Contracts

| # | Contract |
|---|----------|
| C-01 | The panel uses `NSPanel` with `.nonactivatingPanel` style mask. It **never** activates the owning application when shown. |
| C-02 | The panel frame is computed from `NSScreen.main?.visibleFrame` at `show()` time. Width is fixed at 340 pt. Height equals `visibleFrame.height`. The panel's origin x = `visibleFrame.maxX - 340`. |
| C-03 | The panel `level` is `.floating` (above normal windows, below system-level panels). |
| C-04 | The panel has no title bar (`styleMask` includes `.borderless`). |
| C-05 | Pressing `Escape` while the panel is key dismisses it (calls `hide()`). |
| C-06 | The panel is not resizable and not movable by the user in this epic. |
| C-07 | `show()` must complete and the panel must be visible within 100 ms of the call. |

---

## `VocabularySidebarView`

### Responsibility

SwiftUI root view hosted in `VocabularySidebarPanel`. Owns the tab selection state and the daily progress observation. Renders the correct child view for the selected tab.

### Interface (SwiftUI `View`)

```swift
struct VocabularySidebarView: View {
    let repository: VocabularyEntryRepository
    let translationService: TranslationService
}
```

### Behavioural Contracts

| # | Contract |
|---|----------|
| C-08 | Renders a bottom tab bar with four items: Inbox, Learn, Review, Stats. |
| C-09 | The active tab item is visually distinguished from inactive items (e.g. filled vs outline SF Symbol, accent colour). |
| C-10 | Tab switching is immediate — no animation in this epic. |
| C-11 | The selected tab is preserved across show/hide cycles within the same process lifetime (i.e. `@State` is not reset on hide). |
| C-12 | The top of every tab view renders the `DailyProgressBar` component. |
| C-13 | `DailyProgressBar` displays `"\(count) / 20 words"` and a native `ProgressView`. |
| C-14 | `DailyProgress.count` is computed reactively via a `ValueObservation` on `vocabulary_entries`, filtered to today's calendar day. It updates without user interaction when new entries are inserted. |

### Keyboard shortcuts (panel must be key window)

| Shortcut | Action | Scope |
|----------|--------|-------|
| `⌘L` | Switch to Learn tab | any tab |
| `⌘R` | Switch to Review tab | any tab |
| `⌘1` | Switch to Inbox tab | any tab |
| `⌘4` | Switch to Stats tab | any tab |
| `Space` | Reveal hidden translation | Inbox tab (future tabs in Epic 2) |
| `Enter` | Mark current item as Known | Inbox tab (future tabs in Epic 2) |
| `⌘H` | Toggle translation visibility | Inbox tab |
| `Escape` | Dismiss panel | any tab (handled by `NSPanel`) |

**Note**: `⌘R` is bound to Review tab navigation only. "Review later" (F-104) will not conflict because it targets the same action category; if it needs a binding in a later epic, `⌥⌘R` is reserved.

---

## `SidebarTab` Enum

```swift
enum SidebarTab: Hashable, CaseIterable {
    case inbox
    case learn
    case review
    case stats

    var label: String       // e.g. "Inbox"
    var symbolName: String  // SF Symbol name, e.g. "tray"
}
```

---

## `DailyProgress` Value Type

```swift
struct DailyProgress {
    let count: Int
    let target: Int   // Always 20 in this epic

    var fraction: Double  // clamped 0.0...1.0
    var label: String     // "\(count) / \(target) words"
}
```

---

## `StatusItemController` Integration

### Changed behaviour

| Before (Epic 1 baseline) | After (this epic) |
|--------------------------|-------------------|
| Left-click → toggles `NSPopover` | Left-click → calls `panel.toggle()` |
| `NSPopover` with `VocabularyListView` | `VocabularySidebarPanel` with `VocabularySidebarView` |
| Outside-click monitor closes popover | No outside-click monitor; dismiss via Escape / hotkey |

### Contracts

| # | Contract |
|---|----------|
| C-15 | `StatusItemController` holds a `VocabularySidebarPanel` reference instead of `NSPopover`. |
| C-16 | `StatusItemController.toggleSidebar()` is the single entry-point called by both the left-click handler and `AppDelegate` (via `GlobalShortcutManager`). |
| C-17 | The right-click menu retains its pause/resume and quit items; no sidebar-related items are added in this epic. |

---

## `AppDelegate` Rewiring

| # | Contract |
|---|----------|
| C-18 | `GlobalShortcutManager.shared.register` closure calls `statusItemController.toggleSidebar()` (not `toggleCaptureState()`). |
| C-19 | `toggleCaptureState()` remains on `AppDelegate` but is only invoked from the right-click menu item. |
| C-20 | `TranslationSessionHost.install` wiring is unchanged. |

---

## Threading Contracts

| # | Contract |
|---|----------|
| C-21 | `VocabularySidebarPanel.show()`, `hide()`, and `toggle()` must be called on the main thread. |
| C-22 | The `DailyProgress` `ValueObservation` task runs `@MainActor` (same pattern as existing `VocabularyListView` observation). |
| C-23 | Tab switching state mutations are `@MainActor` (SwiftUI `@State` guarantees this). |
