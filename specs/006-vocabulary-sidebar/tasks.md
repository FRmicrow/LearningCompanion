# Tasks: Vocabulary Sidebar — Native Panel

**Input**: Design documents from `specs/006-vocabulary-sidebar/`  
**Branch**: `006-vocabulary-sidebar`  
**Prerequisites**: plan.md ✅ · spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/vocabulary-sidebar.md ✅ · quickstart.md ✅

**Tests**: Not explicitly requested in the spec. No test tasks generated. Existing test suite (`swift test`) must remain green throughout.

**Organization**: Tasks map to the four functional requirements (F-101 → F-104) treated as user stories, plus shared foundational work. Each phase is independently buildable and runnable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[USn]**: Which functional requirement / user story this task belongs to

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Wire the new panel into the app's boot sequence and remove the `NSPopover`. These tasks are prerequisites for every user story.

- [X] T001 Add `VocabularySidebarPanel.swift` stub (empty `final class VocabularySidebarPanel {}`) in `ClipboardVocab/UI/VocabularySidebarPanel.swift`
- [X] T002 [P] Add `VocabularySidebarView.swift` stub (`struct VocabularySidebarView: View { var body: some View { EmptyView() } }`) in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T003 [P] Add `SidebarTabBar.swift` stub in `ClipboardVocab/UI/SidebarTabBar.swift`
- [X] T004 [P] Add `DailyProgressBar.swift` stub in `ClipboardVocab/UI/DailyProgressBar.swift`
- [X] T005 Remove `NSPopover` from `StatusItemController` and replace with a `VocabularySidebarPanel` property; add `toggleSidebar()` method calling `panel.toggle()` in `ClipboardVocab/UI/StatusItemController.swift`
- [X] T006 Rewire `GlobalShortcutManager.shared.register` closure in `AppDelegate.applicationDidFinishLaunching` to call `statusItemController.toggleSidebar()` instead of `toggleCaptureState()` in `ClipboardVocab/App/AppDelegate.swift`
- [X] T007 Verify `swift build` compiles successfully with stubs in place before proceeding

**Checkpoint**: App builds. Menu-bar icon still appears. Global hotkey no longer toggles capture state (it does nothing yet, since stubs are empty). `swift test` passes.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: `SidebarTab` enum and `DailyProgress` value type — needed by every user story phase.

- [X] T008 Implement `SidebarTab` enum (cases: `inbox`, `learn`, `review`, `stats`; `label: String`; `symbolName: String` computed properties) in `ClipboardVocab/UI/SidebarTabBar.swift`
- [X] T009 Implement `DailyProgress` struct (`count: Int`, `target: Int = 20`, `fraction: Double`, `label: String`) in `ClipboardVocab/UI/DailyProgressBar.swift`
- [X] T010 Verify `swift build` still passes

**Checkpoint**: Foundation ready — `SidebarTab` and `DailyProgress` types are usable by all subsequent phases.

---

## Phase 3: F-101 — Floating Sidebar Window (Priority: P1) 🎯 MVP

**Goal**: A real `NSPanel` floats on screen, anchored to the right edge, full-height, no title bar, non-activating. The global hotkey shows/hides it.

**Independent Test** (from quickstart.md — Scenarios 1, 2, 5, 6, 9, 10):
- Press ⌘⇧C → sidebar appears at right edge, full height, no title bar.
- Typing in another app while sidebar is open: characters go to the other app, not the sidebar.
- Press ⌘⇧C again → sidebar closes.
- Press Escape inside sidebar → sidebar closes.
- Other app windows do not cover the sidebar.

### Implementation — F-101

- [X] T011 [US1] Implement `VocabularySidebarPanel` constructor: create `NSPanel` with `styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]`, set `level = .floating`, `isMovable = false`, `isReleasedWhenClosed = false`, `backgroundColor = .windowBackgroundColor` in `ClipboardVocab/UI/VocabularySidebarPanel.swift`
- [X] T012 [US1] Implement `show()`: compute frame from `NSScreen.main?.visibleFrame` (width 340 pt, height = visibleFrame.height, origin.x = visibleFrame.maxX − 340, origin.y = visibleFrame.minY), set panel frame, call `panel.orderFrontRegardless()`, set `isVisible = true` in `ClipboardVocab/UI/VocabularySidebarPanel.swift`
- [X] T013 [US1] Implement `hide()` and `toggle()` methods; expose `var isVisible: Bool` in `ClipboardVocab/UI/VocabularySidebarPanel.swift`
- [X] T014 [US1] Mount `VocabularySidebarView` (stub is fine at this stage) as `contentViewController` via `NSHostingController` inside `VocabularySidebarPanel.init()` in `ClipboardVocab/UI/VocabularySidebarPanel.swift`
- [X] T015 [US1] Pass `repository` and `translationService` through `VocabularySidebarPanel.init(repository:translationService:)` so they reach `VocabularySidebarView` in `ClipboardVocab/UI/VocabularySidebarPanel.swift`
- [X] T016 [US1] Update `StatusItemController.init` to instantiate `VocabularySidebarPanel(repository:translationService:)` and store it; confirm `toggleSidebar()` calls `panel.toggle()` in `ClipboardVocab/UI/StatusItemController.swift`
- [X] T017 [US1] Add Escape key handler: override `cancelOperation(_:)` or use SwiftUI `.onKeyPress(.escape)` on the root view to call `panel.hide()` in `ClipboardVocab/UI/VocabularySidebarPanel.swift`

**Checkpoint** (F-101 done): Global hotkey shows/hides the panel. Panel floats above other windows. Active app keeps focus. Escape closes the panel. `swift test` still green.

---

## Phase 4: F-102 — Multi-View Navigation (Priority: P2)

**Goal**: Bottom tab bar with four tabs. Clicking a tab switches view. Keyboard shortcuts ⌘1, ⌘L, ⌘R, ⌘4 navigate between tabs from within the panel.

**Independent Test** (from quickstart.md — Scenarios 3, 4, 8):
- Open sidebar → Inbox tab is active, tab bar is visible.
- Click Learn → Learn shell visible, Learn tab highlighted.
- Click Inbox / Review / Stats → same.
- ⌘L → Learn; ⌘R → Review; ⌘1 → Inbox; ⌘4 → Stats (panel must be focused).
- Close and reopen sidebar → previously selected tab is still selected.

### Implementation — F-102

- [X] T018 [US2] Implement `SidebarTabBar` SwiftUI view: `HStack` of four tab buttons, each showing `SidebarTab.symbolName` SF Symbol (26 pt) and `SidebarTab.label` text, highlight active tab with accent colour, calls `onSelect(tab)` closure on tap in `ClipboardVocab/UI/SidebarTabBar.swift`
- [X] T019 [US2] Implement `VocabularySidebarView` body: `VStack(spacing: 0)` containing a top content area (shows child view for `selectedTab`) and `SidebarTabBar` pinned to the bottom; `@State var selectedTab: SidebarTab = .inbox` in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T020 [US2] Add `@ViewBuilder` `contentForTab(_:)` function in `VocabularySidebarView` that switches on `selectedTab` and renders: `.inbox` → `VocabularyListView`, `.learn` → placeholder `Text("Learn — coming soon")`, `.review` → placeholder `Text("Review — coming soon")`, `.stats` → placeholder `Text("Stats — coming soon")` in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T021 [US2] Add tab keyboard shortcuts via SwiftUI `.keyboardShortcut` on each tab button or via `.commands` block: `⌘1` → `.inbox`, `⌘L` → `.learn`, `⌘R` → `.review`, `⌘4` → `.stats` in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T022 [US2] Ensure `selectedTab` is declared as `@State` (not `@AppStorage`) so it persists within the session but resets on app relaunch, per contract C-11 in `ClipboardVocab/UI/VocabularySidebarView.swift`

**Checkpoint** (F-102 done): Four-tab bar visible at bottom. Click and keyboard navigation all work. Active tab visually highlighted. Session memory works. `swift test` still green.

---

## Phase 5: F-103 — Daily Progress Bar (Priority: P3)

**Goal**: "Today's Progress" bar at the top of every view, showing `X / 20 words` with a native `ProgressView`. Updates reactively when new entries are captured.

**Independent Test** (from quickstart.md — Scenario 5):
- Open sidebar with an empty DB → bar shows `0 / 20 words`, empty progress.
- Copy a new English word → within ~1 second, counter increments without manual refresh.
- Progress bar fills proportionally.

### Implementation — F-103

- [X] T023 [US3] Implement `DailyProgressBar` SwiftUI view: accepts `progress: DailyProgress`, renders `Text(progress.label)` and `ProgressView(value: progress.fraction)` stacked vertically with padding in `ClipboardVocab/UI/DailyProgressBar.swift`
- [X] T024 [US3] Add `@State private var dailyProgress: DailyProgress` and a `@State private var progressTask: Task<Void, Never>?` to `VocabularySidebarView` in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T025 [US3] Implement `startProgressObservation()` in `VocabularySidebarView`: `ValueObservation.tracking { db in try VocabularyEntry.fetchCount(db, where today filter) }` using GRDB, run as `Task { @MainActor in for try await count in observation.values(in: repository.dbQueue) { dailyProgress = DailyProgress(count: count) } }` in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T026 [US3] Wire `startProgressObservation()` to `.onAppear` and cancel `progressTask` on `.onDisappear` in `VocabularySidebarView` (same pattern as `VocabularyListView`'s `observationTask`) in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T027 [US3] Insert `DailyProgressBar(progress: dailyProgress)` at the top of the `VStack` content area in `VocabularySidebarView`, above the tab content and above the `SidebarTabBar` in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T028 [US3] Add the `L10n` key for `"today_progress_label"` (used in `DailyProgressBar` if any label is localised) in `ClipboardVocab/Resources/Localizable.strings`

**Checkpoint** (F-103 done): Progress bar visible at top of all tabs. Reactive to new captures. `swift test` still green.

---

## Phase 6: F-104 — In-Panel Keyboard Shortcuts (Priority: P4)

**Goal**: While the sidebar is focused, `Space` reveals the hidden translation, `Enter` marks current item known, `⌘H` toggles translation visibility. Shortcuts do not leak to other apps.

**Independent Test** (from quickstart.md — Scenario 4, and spec F-104):
- Open sidebar, click inside it to make it key.
- Press Space → translation for the focused Inbox item is revealed.
- Press Enter → item is marked Known.
- Press ⌘H → translation toggles hidden/visible.
- Press ⌘L while in Inbox → switches to Learn tab (F-102 shortcut, already wired).
- Switch to another app and press Space/Enter → no effect in the vocabulary sidebar.

### Implementation — F-104

- [X] T029 [US4] Add `@State private var isTranslationVisible: Bool = false` to `VocabularyListView` (the Inbox tab child), replacing any existing hard-coded reveal state in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T030 [US4] Implement `Space` key shortcut: add `.onKeyPress(.space) { isTranslationVisible = true; return .handled }` (or equivalent SwiftUI key handler) on the `VocabularyListView` container in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T031 [US4] Implement `⌘H` shortcut: add `.keyboardShortcut("h", modifiers: .command)` on a hidden button or `.onKeyPress` handler that toggles `isTranslationVisible` in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T032 [US4] Implement `Enter` shortcut: wire `.keyboardShortcut(.return, modifiers: [])` to `markKnown()` action (retain the current focused entry) in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T033 [US4] Confirm shortcuts are inactive when another app is frontmost: manual test per quickstart.md Scenario 4 notes (no automated test needed — scoping is guaranteed by SwiftUI's window-focused key handling)

**Checkpoint** (F-104 done): All four in-panel shortcuts work. No leakage to other apps. `swift test` still green.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, localisation completeness, and final validation.

- [X] T034 [P] Remove dead code left from `NSPopover` removal: `buildPopover()`, `openPopover()`, `closePopover()`, `eventMonitor` property, `popoverDidClose(_:)` delegate conformance from `ClipboardVocab/UI/StatusItemController.swift`
- [X] T035 [P] Remove `NSPopoverDelegate` conformance declaration from `StatusItemController` in `ClipboardVocab/UI/StatusItemController.swift`
- [X] T036 [P] Audit all new UI strings (tab labels, progress label, placeholder texts) and ensure each uses `L10n.string(_:)` rather than string literals in all new `.swift` files under `ClipboardVocab/UI/`
- [X] T037 [P] Set fixed panel width constant (`340`) as a named constant `VocabularySidebarPanel.width: CGFloat = 340` instead of inline magic number in `ClipboardVocab/UI/VocabularySidebarPanel.swift`
- [X] T038 Run all quickstart.md validation scenarios manually (Scenarios 1–10) and confirm each passes
- [X] T039 Run `swift test` and confirm all existing tests still pass with zero regressions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T002, T003, T004 can run in parallel.
- **Foundational (Phase 2)**: Depends on Phase 1 completion (T007 checkpoint).
- **F-101 (Phase 3)**: Depends on Phase 2. Blocks nothing — but panels can't be seen without it.
- **F-102 (Phase 4)**: Depends on Phase 3 (needs the panel to exist to show tabs).
- **F-103 (Phase 5)**: Depends on Phase 2 (needs `DailyProgress` type). Can start in parallel with Phase 3 on `DailyProgressBar.swift`; final wiring (T026–T027) requires Phase 4 (`VocabularySidebarView` structure).
- **F-104 (Phase 6)**: Depends on Phase 4 (needs Inbox tab mounted inside the view hierarchy).
- **Polish (Phase 7)**: Depends on all previous phases.

### User Story Dependencies

| Story | Depends on | Can run in parallel with |
|-------|-----------|--------------------------|
| F-101 (US1) | Phase 1 + Phase 2 | — |
| F-102 (US2) | F-101 (panel must exist) | F-103 T023–T024 |
| F-103 (US3) | Phase 2 (DailyProgress type) + F-102 (view structure) | F-101 file creation |
| F-104 (US4) | F-102 (Inbox tab mounted) | — |

### Within Each Phase

- Models / value types before views that consume them
- Stub → build check → flesh out → integration
- Each checkpoint requires `swift build` + `swift test` passing

### Parallel Opportunities

```text
# Phase 1 parallel group (all on separate files):
T002  VocabularySidebarView.swift stub
T003  SidebarTabBar.swift stub
T004  DailyProgressBar.swift stub

# Phase 3 + early Phase 5 (separate files):
T011–T017  VocabularySidebarPanel.swift
T023       DailyProgressBar.swift (implement view, no wiring yet)

# Phase 7 cleanup (all separate files / independent):
T034  Remove NSPopover dead code
T036  Audit L10n strings
T037  Extract width constant
```

---

## Implementation Strategy

### MVP First (F-101 only)

1. Complete Phase 1: Setup stubs + wiring
2. Complete Phase 2: Foundation types
3. Complete Phase 3 (F-101): Real `NSPanel`, show/hide, non-activating
4. **STOP and VALIDATE**: Panel opens from hotkey, floats above other apps, focus not stolen
5. Merge / demo

### Incremental Delivery

1. Phase 1 + 2 → project compiles with stubs (T007 checkpoint)
2. Phase 3 (F-101) → real panel shows/hides ✅
3. Phase 4 (F-102) → tab bar navigation ✅
4. Phase 5 (F-103) → progress bar reactive ✅
5. Phase 6 (F-104) → keyboard shortcuts in panel ✅
6. Phase 7 → polish and cleanup ✅

---

## Notes

- `[P]` tasks operate on different files — safe to run concurrently with one agent per file.
- `[USn]` maps each task to its functional requirement from `spec.md`.
- No new database migrations — all new types are in-memory.
- Do NOT use `try` at `TranslationService.translate(entry:)` call sites (project rule).
- New `ValueObservation` task for daily progress MUST follow the `Task { @MainActor in ... }` + cancel-on-disappear pattern from `VocabularyListView`.
- All new UI strings → `L10n.string(_:)`, never bare string literals.
- `GlobalShortcutManager.shared` stays as a singleton — only its closure is rewired (project rule: singleton must remain alive for app lifetime).
