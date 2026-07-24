# Tasks: Clipboard Vocabulary Capture

**Input**: Design documents from `specs/001-clipboard-vocab-capture/`

**Prerequisites**: [plan.md](plan.md) · [spec.md](spec.md) · [research.md](research.md) · [data-model.md](data-model.md) · [contracts/](contracts/)

**Tests**: Not explicitly requested in spec — unit tests included for core pipeline logic only (critical correctness gates). UI validation follows [quickstart.md](quickstart.md) scenarios manually.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US5)
- Paths follow the project structure defined in [plan.md](plan.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Xcode project initialization, dependency wiring, and app scaffolding

- [X] T001 Create Xcode project `ClipboardVocab` as macOS App, set bundle ID, set `LSUIElement = YES` in `ClipboardVocab/App/Info.plist` to suppress Dock icon
- [X] T002 Add Swift Package dependencies via SPM: `GRDB.swift` (sqlite persistence) via Package.swift (KeyboardShortcuts replaced with inline Carbon GlobalShortcutManager)
- [X] T003 [P] Create top-level directory structure: `ClipboardVocab/App/`, `ClipboardVocab/Services/`, `ClipboardVocab/Persistence/`, `ClipboardVocab/Models/`, `ClipboardVocab/UI/`, `ClipboardVocab/Resources/`, `Tests/Unit/`, `Tests/Integration/`
- [X] T004 [P] Add menu bar icon assets (active + paused variants, template images) to `ClipboardVocab/Resources/Assets.xcassets`
- [X] T005 [P] Create `ClipboardVocab/Resources/Localizable.strings` with French UI strings: empty-state message, "Translation pending" label, "Retry" label, "Seen N times" format string, pause/resume menu item labels
- [X] T006 Configure app entitlements: `com.apple.security.app-sandbox`, `com.apple.security.network.client` (for translation HTTP calls) in `ClipboardVocab/App/ClipboardVocab.entitlements`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data model, database setup, and `CaptureState` enum that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T007 Create `CaptureState` enum (`.active` / `.paused`) in `ClipboardVocab/Models/CaptureState.swift`
- [X] T008 Create `VocabularyEntry` struct conforming to `Codable`, `FetchableRecord`, `PersistableRecord` with all columns from data-model.md (`id`, `englishText`, `frenchTranslation`, `translationStatus`, `seenCount`, `firstCapturedAt`, `lastSeenAt`) in `ClipboardVocab/Models/VocabularyEntry.swift`
- [X] T009 Implement `Database` class: GRDB `DatabaseQueue` setup, `vocabulary_entries` table creation migration, `user_version` schema versioning, database file location at `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite` in `ClipboardVocab/Persistence/Database.swift`
- [X] T010 Implement `VocabularyEntryRepository` with methods: `upsert(englishText:)` (insert new entry as `.pending` or increment `seenCount`+`lastSeenAt`), `update(entry:)`, `delete(id:)`, `fetchAll()` ordered by `firstCapturedAt DESC`, `fetchPending()` (all entries with `translationStatus = 'pending'`) in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T011 Unit test: `VocabularyEntryRepositoryTests` — test insert creates entry with `seenCount=1`, re-insert increments counter (no duplicate), delete removes row, re-capture after delete creates fresh entry with `seenCount=1`, `fetchPending` returns only pending entries in `Tests/Unit/VocabularyEntryRepositoryTests.swift`

**Checkpoint**: Database layer complete — all user story phases can now begin

---

## Phase 3: User Story 1 — Automatic English Word/Phrase Capture (Priority: P1) 🎯 MVP

**Goal**: When the user copies an English word or short phrase (≤50 chars), it is silently detected, translated to French, and saved to the vocabulary list — no user action required.

**Independent Test**: Copy the word `threshold` from any app. Within 3 seconds, open the vocabulary panel (or inspect the SQLite file) and confirm an entry exists with `englishText = "threshold"`, a French translation, and `seenCount = 1`.

### Implementation

- [X] T012 [US1] Implement `LanguageDetectionService`: wraps `NLLanguageRecognizer`, returns detected language + confidence, applies confidence threshold of 0.6 (texts below threshold treated as non-English → discard), in `ClipboardVocab/Services/LanguageDetectionService.swift`
- [X] T013 [US1] Implement `TranslationService`: translate EN→FR using Apple `Translation` framework on macOS 15+; fall back to LibreTranslate HTTP POST on macOS 13–14; return result or throw `TranslationError.unavailable` on network/service failure in `ClipboardVocab/Services/TranslationService.swift`
- [X] T014 [US1] Implement `CaptureProcessorService` full pipeline per `contracts/capture-processor.md`: length gate (>50 chars → discard), natural-language gate (numbers/URLs/paths → discard), language detection gate (not English → discard), duplicate check (upsert via repository), translation request, persistence; expose `CaptureProcessorDelegate` in `ClipboardVocab/Services/CaptureProcessorService.swift`
- [X] T015 [US1] Implement `ClipboardMonitorService` per `contracts/clipboard-monitor.md`: 0.5s `DispatchSourceTimer` polling `NSPasteboard.general.changeCount`, reads `NSPasteboardTypeString` content on change, calls `CaptureProcessorService.process(text:)`, exposes `start()` / `pause()` / `resume()` / `stop()` and `captureState` property in `ClipboardVocab/Services/ClipboardMonitorService.swift`
- [X] T016 [US1] Unit test: `CaptureProcessorTests` — assert each discard path (>50 chars, URL, non-English, low confidence) returns correct `DiscardReason`; assert English word triggers upsert; assert same word twice increments counter not duplicates in `Tests/Unit/CaptureProcessorTests.swift`
- [X] T017 [US1] Unit test: `LanguageDetectionTests` — assert clearly English text returns `.english` with confidence ≥ 0.6; French text returns `.french`; short ambiguous string below threshold returns low-confidence path in `Tests/Unit/LanguageDetectionTests.swift`
- [X] T018 [US1] Integration test: `CaptureToStorageTests` — simulate clipboard change → `ClipboardMonitorService` fires → `CaptureProcessorService` processes → assert entry stored in DB with correct fields in `Tests/Integration/CaptureToStorageTests.swift`
- [X] T019 [US1] Wire `ClipboardMonitorService` startup into `AppDelegate.applicationDidFinishLaunching` in `ClipboardVocab/App/AppDelegate.swift`

**Checkpoint**: US1 complete — clipboard capture, language detection, translation, and persistence all working end-to-end. Validate with quickstart.md Scenarios 1, 3, 4.

---

## Phase 4: User Story 2 — French Text Ignored (Priority: P1)

**Goal**: French and non-English clipboard content, non-text content, and content exceeding 50 characters are all silently discarded — nothing is added to the vocabulary list.

**Independent Test**: Copy `bonjour le monde` → wait 3 seconds → confirm vocabulary list unchanged. Copy a number `12345` → same. Copy a 60-character English sentence → same.

### Implementation

- [X] T020 [US2] Verify `CaptureProcessorService` discard paths (implemented in T014) cover all US2 scenarios: French detection via `LanguageDetectionService`, non-text pasteboard type guard in `ClipboardMonitorService`, length gate, natural-language gate — add any missing guards in `ClipboardVocab/Services/CaptureProcessorService.swift` and `ClipboardVocab/Services/ClipboardMonitorService.swift`
- [X] T021 [US2] Add discard path for non-`NSPasteboardTypeString` clipboard content (images, files) in `ClipboardMonitorService` — no delegate call emitted in `ClipboardVocab/Services/ClipboardMonitorService.swift`
- [X] T022 [US2] Extend `CaptureProcessorTests` to cover: French input → `discardReason = .notEnglish`; numeric string → `discardReason = .noMeaningfulLanguage`; 51-char English → `discardReason = .tooLong` in `Tests/Unit/CaptureProcessorTests.swift`

**Checkpoint**: US2 complete — all rejection paths are verified. Validate with quickstart.md Scenarios 2, 3, 9.

---

## Phase 5: User Story 3 — Review Captured Vocabulary (Priority: P2)

**Goal**: Clicking the menu bar icon opens an `NSPopover` showing the full vocabulary list — each entry displays English text, French translation (or pending badge), and seen count. Empty state shows a French placeholder message.

**Independent Test**: After capturing several words, click the menu bar icon — panel opens within 2 seconds showing all entries in chronological order (most recent first), each with English + French clearly labelled.

### Implementation

- [X] T023 [P] [US3] Implement `VocabularyEntryRow` SwiftUI view: displays `englishText`, `frenchTranslation` (or "Translation pending" badge when `translationStatus == .pending`), "Retry" button when pending, "Seen N times" label (hidden when `seenCount == 1`), formatted `firstCapturedAt` date, delete button — per `contracts/vocabulary-list-ui.md` in `ClipboardVocab/UI/VocabularyEntryRow.swift`
- [X] T024 [P] [US3] Implement `EmptyStateView` SwiftUI view: displays French placeholder message (*"Copiez un mot anglais pour commencer."*) when vocabulary list is empty in `ClipboardVocab/UI/EmptyStateView.swift`
- [X] T025 [US3] Implement `VocabularyListView` SwiftUI view: `List` of `VocabularyEntryRow` entries ordered most-recent-first, shows `EmptyStateView` when list is empty, fixed max-height with vertical scroll in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T026 [US3] Implement `StatusItemController`: creates `NSStatusItem`, sets menu bar icon image, creates `NSPopover` hosting `VocabularyListView`, handles click-to-open/close and outside-click dismiss in `ClipboardVocab/UI/StatusItemController.swift`
- [X] T027 [US3] Wire `StatusItemController` into `AppDelegate` alongside `ClipboardMonitorService`; pass shared `VocabularyEntryRepository` instance to both in `ClipboardVocab/App/AppDelegate.swift`
- [X] T028 [US3] Connect `VocabularyListView` to live data: use GRDB `@Query` or `ValueObservation` to reactively update the list when new entries are inserted or updated in `ClipboardVocab/UI/VocabularyListView.swift`

**Checkpoint**: US3 complete — vocabulary panel opens, displays entries with all fields, empty state works. Validate with quickstart.md Scenarios 1 (then open panel), 10, 12.

---

## Phase 6: User Story 5 — Pause and Resume Capture (Priority: P2)

**Goal**: The user can instantly pause and resume clipboard capture via Command+Shift+C (global shortcut) or a menu bar menu item. The icon changes to indicate paused state. Pause never persists across restarts.

**Independent Test**: Press Command+Shift+C → icon changes → copy English word → wait 3 seconds → panel unchanged → press shortcut again → copy word → entry appears.

### Implementation

- [X] T029 [US5] Register global keyboard shortcut (default: Command+Shift+C) via `GlobalShortcutManager` (Carbon `RegisterEventHotKey`); bind to a `toggleCaptureState()` action in `ClipboardVocab/App/AppDelegate.swift`
- [X] T030 [US5] Implement `toggleCaptureState()` in `AppDelegate`: calls `ClipboardMonitorService.pause()` or `.resume()` based on current state; updates `StatusItemController` icon image (active vs. paused variant from Assets.xcassets) — per `contracts/vocabulary-list-ui.md` icon states in `ClipboardVocab/App/AppDelegate.swift`
- [X] T031 [US5] Add "Pause Capture" / "Resume Capture" menu item to the menu bar right-click or popover header, wired to `toggleCaptureState()` in `ClipboardVocab/UI/StatusItemController.swift`
- [X] T032 [US5] Confirm `ClipboardMonitorService` initializes with `captureState = .active` on every app launch (no pause-state persistence) — verify in `ClipboardVocab/Services/ClipboardMonitorService.swift`

**Checkpoint**: US5 complete — pause/resume via shortcut and menu item both work; icon reflects state; restart always resumes active. Validate with quickstart.md Scenarios 5, 6.

---

## Phase 7: User Story 4 — Delete or Dismiss an Entry (Priority: P3)

**Goal**: The user can delete any vocabulary entry from the list. Deletion is permanent. Re-capturing the same word later creates a fresh entry.

**Independent Test**: Delete the entry for `threshold` → confirm it disappears → copy `threshold` again → confirm a new entry appears with `seenCount = 1`.

### Implementation

- [X] T033 [US4] Wire delete action from `VocabularyEntryRow` delete button to `VocabularyEntryRepository.delete(id:)` — use `.swipeActions` or a button; update the reactive data source so the row disappears immediately in `ClipboardVocab/UI/VocabularyEntryRow.swift` and `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T034 [US4] Confirm hard-delete semantics: `VocabularyEntryRepository.delete(id:)` performs a SQL `DELETE` (not soft delete); verify that re-capturing the same `englishText` after deletion inserts a fresh row with `seenCount = 1` — covered by T011 repository tests; add UI-level confirmation if desired (no undo in v1) in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`

**Checkpoint**: US4 complete — delete removes entry, re-capture creates fresh entry. Validate with quickstart.md Scenario 8.

---

## Phase 8: User Story 3 (Extension) — Translation Pending + Retry (FR-015/016/017)

**Goal**: Entries captured while offline show a "translation pending" badge. Translation retries automatically when connectivity is restored, and the user can trigger a manual retry.

**Independent Test**: Disconnect internet → copy English word → entry appears with "pending" badge → reconnect → translation fills in automatically.

### Implementation

- [X] T035 [P] [US3] Implement connectivity observer in `TranslationService` or `AppDelegate`: use `NWPathMonitor` to detect when network path becomes `.satisfied`; trigger `retryPendingTranslations()` in `ClipboardVocab/App/AppDelegate.swift`
- [X] T036 [P] [US3] Implement `retryPendingTranslations()`: calls `VocabularyEntryRepository.fetchPending()`, iterates entries, calls `TranslationService.translate(entry:)` for each, updates DB on success in `ClipboardVocab/Services/TranslationService.swift`
- [X] T037 [US3] Wire "Retry" button in `VocabularyEntryRow` to call `TranslationService.translate(entry:)` for the specific entry and update the row on success in `ClipboardVocab/UI/VocabularyEntryRow.swift`

**Checkpoint**: Offline capture + auto-retry + manual retry all working. Validate with quickstart.md Scenario 7.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Performance validation, accessibility, edge case hardening, and final validation pass

- [X] T038 [P] Add `accessibilityLabel` values to all interactive UI elements in `VocabularyEntryRow` (delete button, retry button) and `StatusItemController` per `contracts/vocabulary-list-ui.md` accessibility requirements in `ClipboardVocab/UI/VocabularyEntryRow.swift` and `ClipboardVocab/UI/StatusItemController.swift`
- [X] T039 [P] Add "Quit ClipboardVocab" menu item to the menu bar right-click menu (standard macOS convention) in `ClipboardVocab/UI/StatusItemController.swift`
- [X] T040 [P] Verify `ClipboardMonitorService` timer is invalidated cleanly on `applicationWillTerminate` to avoid timer leak in `ClipboardVocab/App/AppDelegate.swift`
- [X] T041 Run all unit and integration tests; confirm all pass in `Tests/` — 22/22 tests passed via `swift test`
- [ ] T042 Validate SC-003: run app for 10 minutes, check Activity Monitor — confirm CPU < 1% idle and RAM < 50 MB
- [ ] T043 Run all 12 validation scenarios from [quickstart.md](quickstart.md); mark each as pass/fail
- [ ] T044 [P] Archive universal binary (arm64 + x86_64) and confirm app runs on a clean macOS 13 VM without Xcode installed
- [X] T045 [P] Add timing assertion to `CaptureToStorageTests`: measure elapsed time from simulated clipboard-change event to confirmed DB insert; assert ≤ 3000ms (SC-001 automated regression guard) in `Tests/Integration/CaptureToStorageTests.swift`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — can start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — **BLOCKS all user story phases**
- **Phase 3 (US1)**: Depends on Phase 2 — core capture pipeline
- **Phase 4 (US2)**: Depends on Phase 3 (shares `CaptureProcessorService`) — extends discard paths
- **Phase 5 (US3)**: Depends on Phase 2 — can be developed in parallel with Phase 3/4 if staffed
- **Phase 6 (US5)**: Depends on Phase 3 (needs `ClipboardMonitorService.pause/resume`) — can overlap with Phase 5
- **Phase 7 (US4)**: Depends on Phase 5 (needs `VocabularyListView` and repository delete) 
- **Phase 8 (US3 ext.)**: Depends on Phase 3 (TranslationService) and Phase 5 (VocabularyEntryRow retry button)
- **Phase 9 (Polish)**: Depends on all story phases complete

### User Story Dependencies

- **US1 (P1)**: Starts after Phase 2 — no story dependencies
- **US2 (P1)**: Shares `CaptureProcessorService` with US1 — best implemented immediately after US1
- **US3 (P2)**: Starts after Phase 2 — independent of US1/US2 data pipeline; can be parallel
- **US5 (P2)**: Requires `ClipboardMonitorService` from US1 — implement after Phase 3
- **US4 (P3)**: Requires `VocabularyListView` from US3 — implement after Phase 5

### Parallel Opportunities Within Phases

- **Phase 1**: T003, T004, T005 all parallel (different files)
- **Phase 3**: T012 and T013 parallel (LanguageDetectionService and TranslationService are independent)
- **Phase 5**: T023 and T024 parallel (`VocabularyEntryRow` and `EmptyStateView` are independent)
- **Phase 8**: T035 and T036 parallel within `TranslationService`
- **Phase 9**: T038, T039, T040, T042, T044, T045 all parallel

---

## Parallel Example: Phase 3 (US1)

```
Parallel track A: T012 — LanguageDetectionService (NLLanguageRecognizer wrapper)
Parallel track B: T013 — TranslationService (Translation framework + LibreTranslate fallback)

After A & B complete:
Sequential:       T014 — CaptureProcessorService (depends on A and B)
Sequential:       T015 — ClipboardMonitorService (depends on T014)
Sequential:       T016, T017, T018 — Unit + integration tests
Sequential:       T019 — Wire into AppDelegate
```

---

## Implementation Strategy

### MVP First (US1 + US2 — Capture Works)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (database + models)
3. Complete Phase 3: US1 (capture, detect, translate, persist)
4. Complete Phase 4: US2 (rejection paths verified)
5. **STOP and VALIDATE**: Use `sqlite3` to inspect the DB (see quickstart.md database inspection section) — confirm entries appear for English and not for French/non-text
6. Ship internal alpha

### Incremental Delivery

1. Setup + Foundational → database layer ready
2. **US1 + US2** → capture pipeline working (validate via sqlite + quickstart Scenarios 1–4, 9)
3. **US3** → vocabulary panel visible (validate via quickstart Scenarios 1, 10, 12)
4. **US5** → pause/resume via shortcut (validate via quickstart Scenarios 5, 6)
5. **US4** → delete entries (validate via quickstart Scenario 8)
6. **US3 ext.** → offline capture + retry (validate via quickstart Scenario 7)
7. Polish → performance, accessibility, final validation

### Single Developer Strategy

Follow phases sequentially (3 → 4 → 5 → 6 → 7 → 8). Phase 5 (UI) can be developed alongside Phase 3 (services) by working on `VocabularyListView` with mock data first, then wiring live data in T028.

---

## Notes

- `[P]` tasks touch different files — safe to implement simultaneously
- Each user story phase ends with a named **Checkpoint** tied to quickstart.md scenarios
- Commit after each task or logical group (one commit per `T0xx` is a reasonable granularity)
- The vocabulary list UI (Phase 5) can be stubbed with static mock data during Phase 3/4 to allow parallel development
- `KeyboardShortcuts` requires the user to grant Accessibility permission on first launch — document this in a first-run prompt
- The `Translation` framework availability check (`if #available(macOS 15, *)`) must be guarded at call sites in `TranslationService`
