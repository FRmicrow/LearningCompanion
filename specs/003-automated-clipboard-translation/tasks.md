---

description: "Task list for Automated Clipboard Translation"
---

# Tasks: Automated Clipboard Translation

**Input**: Design documents from `specs/003-automated-clipboard-translation/`

**Prerequisites**: [plan.md](plan.md) · [spec.md](spec.md) · [research.md](research.md) · [data-model.md](data-model.md) · [contracts/clipboard-monitor.md](contracts/clipboard-monitor.md) · [contracts/capture-processor.md](contracts/capture-processor.md) · [contracts/translation-service.md](contracts/translation-service.md) · [quickstart.md](quickstart.md)

**Tests**: No TDD explicitly requested. Unit and integration tests are included where they validate behaviour that cannot be confirmed through manual observation (persistence, pipeline filtering, latency).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Swift Package Manager project scaffolding and shared model/persistence layer that every user story depends on.

- [X] T001 Initialise Swift Package Manager manifest in `Package.swift` — declare `ClipboardVocab` executable target, `Tests` test target, and GRDB.swift 6.x + KeyboardShortcuts package dependencies
- [X] T002 Create `ClipboardVocab/App/Info.plist` with `LSUIElement = YES` (hides Dock icon, FR-012) and `NSHumanReadableDescription` entry for Accessibility permission prompt
- [X] T003 [P] Create `ClipboardVocab/Models/CaptureState.swift` — `enum CaptureState { case active, paused }` per `data-model.md` In-Memory State section
- [X] T004 [P] Create `ClipboardVocab/Models/VocabularyEntry.swift` — `struct VocabularyEntry: Codable, FetchableRecord, MutablePersistableRecord` with columns `id`, `englishText`, `frenchTranslation`, `translationStatus`, `seenCount`, `firstCapturedAt`, `lastSeenAt`, `isRetained`; nested `TranslationStatus` enum (`pending`/`translated`); `CodingKeys` mapping camelCase to snake_case; `didInsert` for auto-increment — per `data-model.md`
- [X] T005 Create `ClipboardVocab/Persistence/Database.swift` — `DatabaseQueue` singleton at `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite`; GRDB `DatabaseMigrator` with migration `v1` (full schema: table + three indexes per `data-model.md`) and migration `v2` (`ALTER TABLE vocabulary_entries ADD COLUMN isRetained INTEGER NOT NULL DEFAULT 0`)

**Checkpoint**: `swift build` succeeds; `Database.shared` opens the SQLite file and runs both migrations without error. ✅

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Repository, service skeletons, and the clipboard monitor — shared infrastructure required by all three user stories.

**⚠️ CRITICAL**: No user story implementation can begin until T001–T005 and this phase are complete.

- [X] T006 Create `ClipboardVocab/Persistence/VocabularyEntryRepository.swift` — implement `upsert(englishText:) throws -> VocabularyEntry` (insert-or-increment deduplication per `data-model.md`), `update(entry:) throws`, `delete(id:) throws`, `fetchAll() throws -> [VocabularyEntry]`, `fetchPending() throws -> [VocabularyEntry]`, `markRetained(id:_:) throws`, `fetchOldUnretained(before:) throws -> [VocabularyEntry]` — all using `dbQueue.write/read`
- [X] T007 [P] Create `ClipboardVocab/Services/LanguageDetectionService.swift` — wrap `NLLanguageRecognizer`; expose `detect(text:) -> DetectionResult?` and `isEnglish(_:) -> Bool`; constant `confidenceThreshold = 0.6` — per `research.md` Decision 3 and `contracts/capture-processor.md`
- [X] T008 [P] Create `ClipboardVocab/Services/ClipboardMonitorService.swift` — `DispatchSourceTimer` on a background `DispatchQueue` at 500 ms; compare `NSPasteboard.general.changeCount`; only forward non-empty `NSPasteboardTypeString` content; delegate (`ClipboardMonitorDelegate`) called on main thread; `pause()`/`resume()` toggle `captureState` without destroying the timer; `stop()` cancels timer — per `contracts/clipboard-monitor.md`
- [X] T009 Write `Tests/Unit/VocabularyEntryRepositoryTests.swift` — `testUpsert_insertsNewEntry`, `testUpsert_incrementsSeenCount`, `testUpsert_noDuplicateRows`, `testDelete_removesEntry`, `testFetchPending_returnsOnlyPending`, `testMarkRetained_persistsFlag`, `testFetchOldUnretained_excludesRetained`, `testFetchOldUnretained_excludesNewEntries` — all using an in-memory GRDB `DatabaseQueue`

**Checkpoint**: `swift test --filter VocabularyEntryRepository` passes all eight tests. ✅

---

## Phase 3: User Story 1 — Silent Capture & Translation on Copy (Priority: P1) 🎯 MVP

**Goal**: Copying an English word ≤ 50 characters from any app while online causes it to appear in the vocabulary list with its French translation within 3 seconds — with no user interaction required.

**Independent Test**: Copy "threshold" from a browser → wait ≤ 3 s → open vocabulary panel → entry `threshold → seuil` is visible. No duplicate created on second copy. Non-English text, URLs, numbers, and long text are never captured. See [quickstart.md Scenarios 1 and 3](quickstart.md).

### Implementation for User Story 1

- [X] T010 [P] [US1] Create `ClipboardVocab/Services/TranslationService.swift` — `translate(entry:) async` (updates DB on success, leaves `.pending` on failure — never throws); `retryPendingTranslations() async` (fetches all pending, retranslates sequentially); `retryGroup(entries:) async throws -> Int`; internal `translateText(_:) async throws -> String` routing to `translateWithAppleFramework` on macOS 15+ or `translateWithLibreTranslate` as fallback; `libreTranslateURL` var defaulting to `https://libretranslate.com/translate` — per `contracts/translation-service.md` and `research.md` Decision 4
- [X] T011 [P] [US1] Create `ClipboardVocab/Services/CaptureProcessorService.swift` — `process(text:) async` implementing the 6-step pipeline (length gate 50 chars, `hasMeaningfulLanguage` filter for URLs/numbers/paths, `NLLanguageRecognizer` language gate confidence ≥ 0.6 and `.english`, upsert/deduplication, translation for new entries only, delegate callbacks on main thread); `CaptureProcessorDelegate` protocol with `didStore` and `didDiscard(reason: DiscardReason)` — per `contracts/capture-processor.md`
- [X] T012 [US1] Write `Tests/Unit/CaptureProcessorTests.swift` — `testLengthGate_discardsLongText`, `testURLGate_discardsURL`, `testNumberGate_discardsNumeric`, `testPathGate_discardsUnixPath`, `testNonEnglish_discardsText`, `testNewEnglishWord_savesAndTranslates`, `testDuplicate_incrementsSeenCount` — inject mock `LanguageDetectionService` and `TranslationService` stubs; use in-memory repository
- [X] T013 [US1] Create `ClipboardVocab/UI/EmptyStateView.swift` — SwiftUI `View` displaying a French placeholder message when the vocabulary list has no entries
- [X] T014 [US1] Create `ClipboardVocab/UI/VocabularyEntryRow.swift` — SwiftUI row view for a single `VocabularyEntry`; show `englishText`, `frenchTranslation` (or "en cours…" when `.pending`), `seenCount` badge; delete button calling an `onDelete: (Int64) -> Void` callback
- [X] T015 [US1] Create `ClipboardVocab/UI/VocabularyListView.swift` — SwiftUI `List` driven by GRDB `ValueObservation` (`observation.publisher(in: dbQueue)`); observe `VocabularyEntry.order(firstCapturedAt.desc).fetchAll`; renders `VocabularyEntryRow` per entry; shows `EmptyStateView` when entries are empty; frame `width: 340, maxHeight: 480`
- [X] T016 [US1] Create `ClipboardVocab/UI/StatusItemController.swift` — `NSStatusItem` + `NSPopover` lifecycle; `updateIcon(for captureState:)` swaps between normal/paused `NSImage`; `updateMenu(captureState:)` builds right-click `NSMenu` with "Pause/Resume Capture" and "Quit" items; `onToggleCaptureState` and `onQuit` closures wired by `AppDelegate`
- [X] T017 [US1] Create `ClipboardVocab/App/AppDelegate.swift` — `NSApplicationDelegate`; wire `Database`, `VocabularyEntryRepository`, `TranslationService`, `LanguageDetectionService`, `CaptureProcessorService`, `ClipboardMonitorService`, `StatusItemController` in `applicationDidFinishLaunching`; implement `ClipboardMonitorDelegate.clipboardMonitor(_:didCapture:)` to dispatch `captureProcessor.process(text:)` in a `Task`; implement `toggleCaptureState()` updating monitor + icon + menu
- [X] T018 [US1] Create `ClipboardVocab/App/main.swift` — `NSApplication.shared.delegate = AppDelegate(); NSApp.run()`
- [X] T019 [US1] Write `Tests/Integration/CaptureToStorageTests.swift` — `testCaptureLatencyWithinThreeSeconds`: constructs a real `CaptureProcessorService` with in-memory DB and a stubbed `TranslationService` that resolves instantly; records wall-clock time from `process(text:)` call to `didStore` delegate callback; asserts elapsed ≤ 3000 ms (SC-001 guard)

**Checkpoint**: User Story 1 fully functional — copy an English word → appears in vocabulary panel with French translation within 3 seconds. SC-001 integration test passes. ✅

---

## Phase 4: User Story 2 — Offline Resilience (Priority: P2)

**Goal**: Words copied while offline are immediately saved as `.pending`; they are automatically translated within 5 seconds of network connectivity being restored — no user action required.

**Independent Test**: Disable Wi-Fi → copy "resilience" → entry visible as pending immediately → re-enable Wi-Fi → entry updates to `resilience → résilience` within 5 seconds. See [quickstart.md Scenario 2](quickstart.md).

### Implementation for User Story 2

- [X] T020 [US2] Add `NWPathMonitor` connectivity observer to `ClipboardVocab/App/AppDelegate.swift` — in `startConnectivityMonitor()`, create `NWPathMonitor`, set `pathUpdateHandler` to call `translationService.retryPendingTranslations()` in a `Task` when `path.status == .satisfied`; start monitor on `DispatchQueue.global(qos: .background)`; cancel in `applicationWillTerminate`
- [X] T021 [US2] Verify `TranslationService.translate(entry:)` in `ClipboardVocab/Services/TranslationService.swift` correctly leaves entry as `.pending` (no DB update) on `URLError`, non-2xx HTTP response, and JSON decode failure — add inline `// MARK: Offline behaviour` comment block explaining the pending/retry contract
- [X] T022 [US2] Write `Tests/Unit/TranslationServiceTests.swift` — `testTranslate_updatesStatusOnSuccess` (stub URLSession returning valid LibreTranslate JSON), `testTranslate_leavesPendingOnNetworkError` (stub URLSession throwing `URLError.notConnectedToInternet`), `testRetryPendingTranslations_translatesAllPending` (seed two pending entries; verify both become `.translated` after `retryPendingTranslations()`)

**Checkpoint**: Offline-copy → pending entry visible immediately. Reconnect → pending entries translated within 5 seconds. `swift test --filter TranslationService` passes. ✅

---

## Phase 5: User Story 3 — Pause & Resume Capture (Priority: P3)

**Goal**: ⌘ Shift C (or menu bar context menu) instantly pauses clipboard capture; no new entries are created while paused. A second press resumes capture. The menu bar icon reflects the current state. Pause state is never persisted — app always starts capturing.

**Independent Test**: Press ⌘ Shift C → icon changes to paused variant → copy a word → no entry created → press ⌘ Shift C → copy same word → entry appears. App restart always starts in active state. See [quickstart.md Scenarios 4 and 5](quickstart.md).

### Implementation for User Story 3

- [X] T023 [US3] Create `ClipboardVocab/Services/GlobalShortcutManager.swift` — wrap Carbon `RegisterEventHotKey` for ⌘ Shift C; `register(handler: @escaping () -> Void)` installs the hotkey and stores the callback; `unregister()` removes it; implement as a singleton `GlobalShortcutManager.shared` — per `research.md` Decision 6
- [X] T024 [US3] Wire `GlobalShortcutManager` in `ClipboardVocab/App/AppDelegate.swift` — call `GlobalShortcutManager.shared.register { [weak self] in self?.toggleCaptureState() }` in `applicationDidFinishLaunching`; call `GlobalShortcutManager.shared.unregister()` in `applicationWillTerminate`
- [X] T025 [US3] Confirm `ClipboardVocab/Services/ClipboardMonitorService.swift` `pause()`/`resume()` correctly set `captureState` without cancelling the timer and that `captureState` is always `.active` on `init` (FR-011) — add a comment confirming the invariant
- [X] T026 [US3] Write `Tests/Unit/ClipboardMonitorTests.swift` — `testInitialState_isActive`, `testPause_setsStateToPaused`, `testResume_setsStateToActive`, `testStop_nilsTimer` — instantiate `ClipboardMonitorService` directly (no running loop needed for state assertions)
- [X] T027 [US3] Add `ClipboardVocab/Resources/Assets.xcassets/MenuBarIcon.imageset/` and `MenuBarIconPaused.imageset/` — provide 16×16 and 32×32 PNG assets (template images) for active and paused states; wire in `StatusItemController.updateIcon(for:)` using `NSImage(named:)`

**Checkpoint**: ⌘ Shift C toggles capture and icon. No words captured while paused. App always starts active. `swift test --filter ClipboardMonitor` passes. ✅

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Language detection accuracy verification, accessibility, end-to-end quickstart validation, and documentation.

- [X] T028 [P] Write `Tests/Unit/LanguageDetectionTests.swift` — `testEnglishWord_isEnglish`, `testFrenchWord_notEnglish`, `testURL_lowConfidenceOrNotEnglish`, `testShortNumber_notMeaningfulLanguage` (call `isEnglish` and `detect` with a representative corpus of English and French single words; assert > 95% correct per SC-003)
- [X] T029 [P] Run all quickstart validation scenarios from [quickstart.md](quickstart.md) — Scenario 1 (copy while online), Scenario 2 (offline + reconnect), Scenario 3 (noise filtering), Scenario 4 (pause/resume), Scenario 5 (restart resets state), Scenario 6 (idle CPU < 1%) — confirm all expected outcomes
- [X] T030 [P] Run `swift test` and confirm all unit and integration tests pass — `VocabularyEntryRepositoryTests`, `CaptureProcessorTests`, `TranslationServiceTests`, `ClipboardMonitorTests`, `LanguageDetectionTests`, `CaptureToStorageTests`
- [X] T031 [P] Verify `ClipboardVocab/App/Info.plist` includes `NSAppleEventsUsageDescription` (or relevant privacy key) for Accessibility prompt; confirm `LSUIElement = YES` hides the Dock icon on launch (FR-012)
- [X] T032 [P] Add inline `// Per contracts/clipboard-monitor.md`, `// Per contracts/capture-processor.md`, `// Per contracts/translation-service.md` doc-comment cross-references in `ClipboardMonitorService.swift`, `CaptureProcessorService.swift`, and `TranslationService.swift` respectively

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (T001–T005 must compile for T006–T009)
- **Phase 3 (US1)**: Depends on Phase 2 completion — requires `VocabularyEntryRepository`, `LanguageDetectionService`, and `ClipboardMonitorService`
- **Phase 4 (US2)**: Depends on Phase 2 and Phase 3 — extends `AppDelegate` and `TranslationService` created in US1
- **Phase 5 (US3)**: Depends on Phase 2 — can start in parallel with Phase 4 (`GlobalShortcutManager` is a new, independent file)
- **Phase 6 (Polish)**: Depends on all story phases being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no dependency on US2 or US3
- **US2 (P2)**: Can start after Phase 3 (US1) — extends `AppDelegate` and calls existing `TranslationService`
- **US3 (P3)**: Can start after Phase 2 — independent of US2 (different files)

### Within Each Phase

- Models before services (T003–T004 before T010–T011)
- Repository before processor (T006 before T011)
- Services before UI wiring (T010–T011 before T014–T016)
- Core wiring before integration test (T017 before T019)

### Parallel Opportunities

- T003 and T004 (model files) can run in parallel — different files
- T007 and T008 (language detector + clipboard monitor) can run in parallel — different files
- T010 and T011 (translation service + capture processor) can run in parallel — different files
- T013 and T014 (empty state view + entry row) can run in parallel — different files
- T020 and T021 (connectivity observer + translation offline path) can run in parallel — different concerns
- T023 and T025 (global shortcut + pause invariant) can run in parallel — different files
- T028, T029, T030, T031, T032 (all polish tasks) can run in parallel

---

## Parallel Example: Phase 2 (Foundational)

```
Parallel batch A — service layer (independent files):
  T007: LanguageDetectionService.swift
  T008: ClipboardMonitorService.swift

Sequential after T006:
  T009: VocabularyEntryRepositoryTests.swift (targets T006 methods)
```

## Parallel Example: Phase 3 (US1 — Services)

```
Parallel batch A (independent files):
  T010: TranslationService.swift
  T011: CaptureProcessorService.swift

Parallel batch B (independent files, after T013/T014):
  T013: EmptyStateView.swift
  T014: VocabularyEntryRow.swift

Sequential after A + B:
  T015: VocabularyListView.swift (depends on T014)
  T016: StatusItemController.swift (depends on T015)
  T017: AppDelegate.swift (depends on T015 + T016 + T010 + T011 + T008)
  T018: main.swift (depends on T017)
  T019: CaptureToStorageTests.swift (depends on T010 + T011 + T006)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Models + persistence (T001–T005)
2. Complete Phase 2: Repository + core services (T006–T009)
3. Complete Phase 3: Capture pipeline + UI wiring (T010–T019)
4. **STOP and VALIDATE**: Run quickstart Scenario 1 + Scenario 3 (noise filtering)
5. Ship / demo the end-to-end silent-capture experience

### Incremental Delivery

1. Phase 1 + Phase 2 → shared foundation ready
2. Phase 3 (US1) → full capture + translation loop → validate → demo
3. Phase 4 (US2) → offline resilience → validate → demo
4. Phase 5 (US3) → pause/resume → validate → demo
5. Phase 6 → polish, tests, quickstart sign-off

### Parallel Team Strategy (2 developers)

1. Both complete Phase 1 + Phase 2 together
2. After Phase 2:
   - **Dev A**: Phase 3 (US1) → then Phase 4 (US2)
   - **Dev B**: Phase 5 (US3) in parallel — independent files
3. Both complete Phase 6 together

---

## Notes

- [P] tasks operate on different files and have no unresolved inter-dependencies at the time they run
- [Story] labels map each task to a specific user story for traceability back to `spec.md`
- `TranslationService.translate(entry:)` NEVER throws — callers need not wrap it in `try`; only `retryGroup` throws (per `contracts/translation-service.md`)
- GRDB `ValueObservation` automatically pushes DB changes to `@State var entries` in `VocabularyListView` — no manual `NotificationCenter` refresh needed
- `ClipboardMonitorService` timer keeps firing during pause — only the delegate call is suppressed; this avoids timer destruction/recreation latency on toggle
- Commit after each checkpoint to keep git history aligned with independently testable increments
