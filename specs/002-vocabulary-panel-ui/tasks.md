---

description: "Task list for Vocabulary Panel UI"
---

# Tasks: Vocabulary Panel UI

**Input**: Design documents from `specs/002-vocabulary-panel-ui/`

**Prerequisites**: [plan.md](plan.md) · [spec.md](spec.md) · [research.md](research.md) · [data-model.md](data-model.md) · [contracts/vocabulary-panel-ui.md](contracts/vocabulary-panel-ui.md) · [quickstart.md](quickstart.md)

**Tests**: No TDD explicitly requested. Unit tests for repository methods are included (they validate persistence logic that cannot be visually confirmed).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the `isRetained` field to the model and database — required by every subsequent phase.

- [X] T001 Add `isRetained: Bool` field to `VocabularyEntry` in `ClipboardVocab/Models/VocabularyEntry.swift` (new column mapping `isRetained`, default `false`)
- [X] T002 Register GRDB v2 migration in `ClipboardVocab/Persistence/Database.swift` — `ALTER TABLE vocabulary_entries ADD COLUMN isRetained INTEGER NOT NULL DEFAULT 0`

**Checkpoint**: Build succeeds; existing entries receive `isRetained = false` after first launch post-migration. ✅

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Repository methods and service additions that all user story phases depend on.

**⚠️ CRITICAL**: No user story implementation can begin until T001–T002 and this phase are complete.

- [X] T003 [P] Add `markRetained(id: Int64, _ retained: Bool) throws` to `ClipboardVocab/Persistence/VocabularyEntryRepository.swift` — updates `isRetained` for a single row
- [X] T004 [P] Add `fetchOldUnretained(before cutoff: Date) throws -> [VocabularyEntry]` to `ClipboardVocab/Persistence/VocabularyEntryRepository.swift` — fetches rows where `isRetained = 0 AND firstCapturedAt < cutoff`
- [X] T005 [P] Add `retryGroup(entries: [VocabularyEntry]) async throws -> Int` to `ClipboardVocab/Services/TranslationService.swift` — iterates entries, calls `translate(entry:)` on each, returns count of successfully translated entries; throws if the service is wholly unavailable
- [X] T006 [P] Write `testMarkRetained_persistsTrue` and `testMarkRetained_persistsFalse` unit tests in `Tests/VocabularyEntryRepositoryTests.swift` (creates in-memory DB, inserts entry, toggles `isRetained`, asserts persisted value)
- [X] T007 [P] Write `testFetchOldUnretained_excludesRetained` and `testFetchOldUnretained_excludesNewEntries` unit tests in `Tests/VocabularyEntryRepositoryTests.swift`

**Checkpoint**: `swift test` passes; `markRetained` and `fetchOldUnretained` work correctly against an in-memory GRDB database. ✅

---

## Phase 3: User Story 1 — Review Today's Vocabulary (Priority: P1) 🎯 MVP

**Goal**: Left-side panel displays date-grouped entries with `word → translation` format and functional "ok" checkboxes whose state persists across restarts.

**Independent Test**: Launch the app with at least one captured word → panel opens to the left of/below the menu bar icon → entries appear under today's date heading → "ok" checkbox toggles and survives app restart. See [quickstart.md Scenario 1](quickstart.md).

### Implementation for User Story 1

- [X] T008 [US1] Create `ClipboardVocab/UI/VocabularyDateGroupSection.swift` — SwiftUI `Section` view accepting `dateLabel: String`, `entries: [VocabularyEntry]`, `onRetainToggle: (Int64, Bool) -> Void`, and `onRetryGroup: () async -> Void` callbacks; renders date heading + retry button placeholder (button wired in US2) + entry rows
- [X] T009 [US1] Update `ClipboardVocab/UI/VocabularyEntryRow.swift` — replace per-entry retry link with an `isRetained: Binding<Bool>` `Toggle` labelled "ok"; apply strikethrough/muted style when `isRetained == true`; retain delete button; remove standalone "Retry" link (retry moves to group header in US2)
- [X] T010 [US1] Refactor `ClipboardVocab/UI/VocabularyListView.swift` — replace flat `List` with a grouped layout: compute `Dictionary(grouping: entries, by: calendarDay)`, render one `VocabularyDateGroupSection` per day (sorted newest-first), wire `onRetainToggle` to call `repository.markRetained(id:_:)` in a `Task`; keep `EmptyStateView` for zero-entry state; widen frame to `width: 380, maxHeight: 500`
- [X] T011 [US1] Add `accessibilityLabel("Mark \(entry.englishText) as retained")` to the "ok" `Toggle` in `ClipboardVocab/UI/VocabularyEntryRow.swift`

**Checkpoint**: User Story 1 fully functional — date groups visible, checkboxes toggle and persist across restart. ✅

---

## Phase 4: User Story 2 — Retry Translation for a Date Group (Priority: P2)

**Goal**: Each date-group header shows a "Réessayer la traduction" button that retranslates all entries in that group, with a spinner during the operation.

**Independent Test**: Force a `.pending` entry into a date group → click the group's retry button → spinner appears, button disables → translation appears and button re-enables. See [quickstart.md Scenario 2](quickstart.md).

### Implementation for User Story 2

- [X] T012 [US2] Add `@State private var isRetrying: Bool` to `VocabularyDateGroupSection` in `ClipboardVocab/UI/VocabularyDateGroupSection.swift` — controls spinner visibility and button disabled state
- [X] T013 [US2] Wire the "Réessayer la traduction" `Button` in `VocabularyDateGroupSection` (`ClipboardVocab/UI/VocabularyDateGroupSection.swift`) — on tap: set `isRetrying = true`, call `await onRetryGroup()`, set `isRetrying = false`; show `ProgressView` spinner inline when `isRetrying`; disable button while retrying
- [X] T014 [US2] Wire `onRetryGroup` closure in `VocabularyListView` (`ClipboardVocab/UI/VocabularyListView.swift`) — for each date group, pass a closure that calls `await translationService.retryGroup(entries: groupEntries)`
- [X] T015 [US2] Add inline error state to `VocabularyDateGroupSection` (`ClipboardVocab/UI/VocabularyDateGroupSection.swift`) — catch any throw from `retryGroup` or detect zero successful translations (returned count == 0); show a brief error label under the header; set `isRetrying = false` in **all** exit paths (success and failure) so the button always re-enables; clear error label on next successful retry
- [X] T016 [US2] Add `accessibilityLabel("Retry translation for \(dateLabel)")` to the retry button in `ClipboardVocab/UI/VocabularyDateGroupSection.swift`

**Checkpoint**: Retry button functional with correct spinner lifecycle and error feedback. User Story 1 unaffected. ✅

---

## Phase 5: User Story 3 — Old Unretained Words Section (Priority: P3)

**Goal**: A clearly labelled "Mots non retenus (>1 semaine)" section at the bottom of the panel lists all entries older than 7 days with `isRetained == false`; checking one removes it from the section.

**Independent Test**: Insert a DB entry with `firstCapturedAt` 8 days ago and `isRetained = 0` → section appears at panel bottom with the entry → check "ok" → entry leaves the section. See [quickstart.md Scenario 3](quickstart.md).

### Implementation for User Story 3

- [X] T017 [US3] Create `ClipboardVocab/UI/OldUnretainedWordsSection.swift` — SwiftUI `Section` view accepting `entries: [VocabularyEntry]` and `onRetainToggle: (Int64, Bool) -> Void`; renders section header "Mots non retenus (>1 semaine)" + reuses `VocabularyEntryRow` for each entry; hides itself when `entries.isEmpty`
- [X] T018 [US3] Add old-unretained derived state to `VocabularyListView` (`ClipboardVocab/UI/VocabularyListView.swift`) — compute `oldUnretained` as `entries.filter { !$0.isRetained && $0.firstCapturedAt < Date().addingTimeInterval(-7 * 24 * 3600) }` inside the view body (or as a computed property); render `OldUnretainedWordsSection` after date groups when `oldUnretained` is non-empty
- [X] T019 [US3] Add `accessibilityLabel("Old unretained words, more than one week")` to the section header in `ClipboardVocab/UI/OldUnretainedWordsSection.swift`
- [X] T020 [US3] Write `testDateGrouping_groupsByCalendarDay` unit test in `Tests/VocabularyListViewModelTests.swift` (or inline helper) — inserts entries on two different dates, asserts grouping produces two groups with correct members

**Checkpoint**: Old unretained section appears/hides correctly; checking a word removes it from the section. All three user stories function independently. ✅

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Accessibility completeness, empty-state edge case, and quickstart validation.

- [X] T021 [P] Verify `accessibilityLabel` on all interactive elements per [contracts/vocabulary-panel-ui.md Accessibility section](contracts/vocabulary-panel-ui.md) — section headers, retry button, "ok" toggle, delete button — in all new/modified UI files
- [X] T022 [P] Confirm `EmptyStateView` is still shown (and date groups / old words section are hidden) when the total entry count is zero — smoke-test in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T023 Run all five quickstart validation scenarios from [quickstart.md](quickstart.md) and confirm expected outcomes
- [X] T024 [P] Run `swift test` and confirm all unit tests pass (T006, T007, T020)
- [X] T025 [P] Update `specs/001-clipboard-vocab-capture/contracts/vocabulary-list-ui.md` with a deprecation note pointing to the new `contracts/vocabulary-panel-ui.md` (the per-entry retry link is superseded)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (T001, T002 must be complete for the model to compile)
- **Phase 3 (US1)**: Depends on Phase 2 completion — blocks US2 and US3 (they build on the grouped layout)
- **Phase 4 (US2)**: Depends on Phase 3 (retry button lives inside `VocabularyDateGroupSection` created in US1)
- **Phase 5 (US3)**: Depends on Phase 2; can start in parallel with Phase 4 (different files)
- **Phase 6 (Polish)**: Depends on all story phases being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no dependency on US2 or US3
- **US2 (P2)**: Can start after Phase 3 (US1) completes — extends `VocabularyDateGroupSection`
- **US3 (P3)**: Can start after Phase 2 — independent of US2 (different view file)

### Within Each Phase

- Models before views (T001 before T008–T011)
- Repository methods before view wiring (T003–T005 before T008–T018)
- Core view implementation before accessibility polish

### Parallel Opportunities

- T003, T004, T005 (repository + service additions) can all run in parallel — different methods/files
- T006 and T007 (unit tests) can run in parallel with T003–T005 (tests target separate file)
- T008, T009 (new view file + row update) can run in parallel — different files
- T012–T016 (US2) and T017–T020 (US3) can be worked in parallel by two developers once Phase 3 is done
- T021, T022, T024, T025 (polish) can all run in parallel

---

## Parallel Example: Phase 2 (Foundational)

```
Parallel batch A — repository layer (T003, T004 in same file, sequential within file):
  T003: markRetained(id:_:) in VocabularyEntryRepository.swift
  T004: fetchOldUnretained(before:) in VocabularyEntryRepository.swift

Parallel batch B — service layer:
  T005: retryGroup(entries:) in TranslationService.swift

Parallel batch C — tests (separate file, no dependency on A/B to write):
  T006: testMarkRetained_* in Tests/VocabularyEntryRepositoryTests.swift
  T007: testFetchOldUnretained_* in Tests/VocabularyEntryRepositoryTests.swift
```

## Parallel Example: Phase 3 (US1)

```
Parallel batch A:
  T008: Create VocabularyDateGroupSection.swift (new file)
  T009: Update VocabularyEntryRow.swift (different file)

Sequential after A:
  T010: Refactor VocabularyListView.swift (depends on T008+T009 API)
  T011: Accessibility labels in VocabularyEntryRow.swift (after T009)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Model + migration (T001–T002)
2. Complete Phase 2: Repository + service methods (T003–T007)
3. Complete Phase 3: Grouped panel + checkboxes (T008–T011)
4. **STOP and VALIDATE**: Run quickstart Scenario 1 + Scenario 4 (empty state)
5. Ship / demo the date-grouped panel with working "ok" checkboxes

### Incremental Delivery

1. Phase 1 + Phase 2 → shared foundation ready
2. Phase 3 (US1) → grouped panel with checkboxes → validate → demo
3. Phase 4 (US2) → group-level retry button → validate → demo
4. Phase 5 (US3) → old unretained section → validate → demo
5. Phase 6 → polish and contract update

### Parallel Team Strategy (2 developers)

1. Both complete Phase 1 + Phase 2 together
2. After Phase 2:
   - **Dev A**: Phase 3 (US1) → then Phase 4 (US2)
   - **Dev B**: Phase 5 (US3) in parallel with Dev A's Phase 3/4
3. Both complete Phase 6 together

---

## Notes

- [P] tasks operate on different files and have no unresolved inter-dependencies at the time they run
- [Story] labels map each task to a specific user story for traceability back to spec.md
- The `isRetained` `Toggle` in `VocabularyEntryRow` is a `Binding<Bool>` — the parent view owns the write operation to keep row logic side-effect-free
- GRDB `ValueObservation` will automatically push DB changes to `@State var entries` after `markRetained` writes — no manual refresh needed
- The per-entry "Retry" link from v1 (`VocabularyEntryRow`) is **removed** in T009; retry is now exclusively a per-group action (T012–T014)
- Commit after each checkpoint to keep git history aligned with independently testable increments
