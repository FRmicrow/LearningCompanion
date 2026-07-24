# Research: Vocabulary Sidebar — Native Panel

**Feature**: 006-vocabulary-sidebar  
**Date**: 2025-07-15

---

## Decision 1: Window type — NSPanel vs NSWindow

**Decision**: Use `NSPanel` with `styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]`  
**Rationale**: `NSPanel` with `.nonactivatingPanel` is the AppKit primitive designed for floating utility surfaces that must not steal key focus from the active application. An `NSWindow` with `level = .floating` would also float, but without `.nonactivatingPanel` it activates the app on click — exactly what the spec forbids. `NSPanel` documents this behaviour as its primary use-case (Inspector panels, quick-entry surfaces like Raycast/Alfred use the same approach).  
**Alternatives considered**:
- Plain `NSWindow` with `.floating` level — rejected because it activates the owning app on show, stealing focus from the user's active app.
- `NSPopover` (current) — rejected because it is tied to an anchor view, has fixed width, cannot span full screen height, and has opinionated arrow decoration.

---

## Decision 2: SwiftUI hosting strategy

**Decision**: Wrap the SwiftUI panel content in a single `NSHostingController` rooted to a new `VocabularySidebarView` (a SwiftUI `View`). Host it in the `NSPanel` via `contentViewController`.  
**Rationale**: The existing `VocabularyListView` is already a SwiftUI view hosted in `NSHostingController`. Extending that pattern is consistent with the project's established architecture. The new `VocabularySidebarView` will own the tab state and render the appropriate child view per tab; `VocabularyListView` will become one of those children (refactored to be the Inbox tab).  
**Alternatives considered**:
- Pure AppKit tab bar — rejected because all existing UI is SwiftUI; mixing would add significant complexity.
- `SwiftUI.TabView` — considered but rejected because it renders a macOS-style horizontal tab picker that does not match the bottom-anchored icon-bar design described in the spec. A custom `HStack`-based tab bar gives full control over layout.

---

## Decision 3: Panel positioning and sizing

**Decision**: At show-time, compute the panel frame from `NSScreen.main?.visibleFrame` (which already excludes the menu bar and Dock) and anchor it to the right edge. Fixed width of 340 pt.  
**Rationale**: `visibleFrame` is the canonical AppKit API for usable screen space. Using it avoids manual calculations against `frame` + menu bar height. Width of 340 pt fits the existing `VocabularyListView` (currently fixed at 380 pt — this will be slightly narrowed during layout refactoring or kept at 380 pt if content demands it; 340–380 pt is the acceptable range).  
**Alternatives considered**:
- `NSScreen.main?.frame` — rejected because it includes menu bar and Dock areas, causing overlap.
- Dynamic width — rejected as out of scope per the spec assumptions.

---

## Decision 4: Tab bar implementation

**Decision**: Custom SwiftUI `HStack` bottom bar with four icon+label items backed by a `@State var selectedTab: SidebarTab` enum stored in `VocabularySidebarView`.  
**Rationale**: `TabView` on macOS renders a segmented control or tab strip at the top, not a bottom icon bar. A hand-rolled bottom bar matches the design intent (Inbox / Learn / Review / Stats icons) and requires no additional dependencies.  
**Alternatives considered**:
- `TabView` — rejected (see Decision 2).
- A separate `NSToolbar` — rejected as AppKit-only and inconsistent with the SwiftUI hosting strategy.

---

## Decision 5: In-panel keyboard shortcuts

**Decision**: Implement with SwiftUI `.keyboardShortcut()` modifier on buttons within each tab view, and `.onKeyPress(.space, ...)` / `.onKeyPress(.return, ...)` for unmodified key actions.  
**Rationale**: SwiftUI keyboard shortcut modifiers are the idiomatic approach for in-window key bindings. They are automatically scoped to when the window/panel is key — no explicit guard needed, satisfying the spec requirement that shortcuts must not leak to other apps.  
**Note on conflict with global hotkey**: `⌘R` is used both as an in-panel "Review later" shortcut (F-104) and as tab navigation to the Review view (F-102). Resolution: the tab shortcut takes priority in the panel (tab navigation is more common). The "Review later" action will be bound to a button and accessible via the tab shortcut label without a duplicate `⌘R` binding. This avoids an ambiguous shortcut collision.  
**Alternatives considered**:
- Carbon `RegisterEventHotKey` for in-panel shortcuts — rejected because Carbon hotkeys are global and cannot be scoped to a focused window.
- `NSMenu` key equivalents — rejected because the panel has no menu bar.

---

## Decision 6: Daily progress data source

**Decision**: Compute `DailyProgress` by querying `VocabularyEntryRepository` for entries whose `firstCapturedAt` falls within today's calendar day. Compute this live via `ValueObservation` so the bar updates reactively when new words are captured.  
**Rationale**: `firstCapturedAt` is already indexed and the only date field on `VocabularyEntry` available in this epic. Future epics may refine the "progress" definition (e.g. reviewed words), but for this epic "words saved today" is the appropriate and self-contained metric.  
**Alternatives considered**:
- UserDefaults counter — rejected because it would fall out of sync with the DB and cannot be reset reliably without app restart.
- Separate `DailyProgress` DB table — rejected as over-engineering; a filtered count query on the existing table is sufficient.

---

## Decision 7: `StatusItemController` migration

**Decision**: Replace the `NSPopover` in `StatusItemController` with show/hide calls on the new `VocabularySidebarPanel`. The left-click handler on the status item button will call `panel.toggle()` instead of `togglePopover()`. The existing outside-click `NSEvent.addGlobalMonitorForEvents` pattern is removed — the panel is dismissed via Escape key or re-triggering the hotkey/menu-bar click.  
**Rationale**: The spec states the panel is dismissed by Escape or the global hotkey. An outside-click auto-dismiss would conflict with the "non-activating, non-focus-stealing" behaviour goal, because detecting outside clicks reliably while the panel is non-activating requires special handling. The Escape / toggle model is simpler and matches Raycast/Alfred patterns.  
**Alternatives considered**:
- Keep `NSPopover` alongside the new panel — rejected because the spec explicitly replaces it.
- Keep outside-click monitor — deferred to Epic 6 (polish) if users request it.

---

## Decision 8: `GlobalShortcutManager` — action rewiring

**Decision**: The existing `GlobalShortcutManager` currently calls `toggleCaptureState()` (pause/resume clipboard monitoring). Per the spec, the hotkey should toggle the **sidebar panel** visibility, not the capture state. The capture-state toggle moves to a menu-only action (right-click menu item already exists). `AppDelegate` rewires `GlobalShortcutManager.shared.register` to call `statusItemController.toggleSidebar()` instead.  
**Rationale**: The spec states "the existing global hotkey continues to be used to toggle the sidebar." Making the hotkey open the sidebar is the natural outcome of this epic's intent. Capture pausing remains accessible via the right-click menu.  
**Alternatives considered**:
- Register a second hotkey for the sidebar — rejected to avoid shortcut proliferation.
- Keep the hotkey on capture toggle and use only menu-bar click to open the sidebar — rejected because the spec is explicit about hotkey = sidebar toggle.
