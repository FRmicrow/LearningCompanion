---
description: "Task list for Translation Reliability bug fixes"
---

# Tasks: Translation Reliability

**Input**: Design documents from `specs/004-translation-reliability/`

**Branch**: `004-translation-reliability`

**Prerequisites**: plan.md ✅ · spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/translation-service-v2.md ✅ · quickstart.md ✅

**Tests**: Not explicitly requested. Existing test suite (`swift test`) is used as the regression gate. No new test tasks are generated (see research.md Decision 7 — the three bugs are SwiftUI lifecycle issues not amenable to unit testing without new dependencies).

**Organization**: Tasks are grouped by user story. Each fix is a self-contained change to a single file, enabling independent verification.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[Story]**: User story this task belongs to ([US1], [US2], [US3])

---

## Phase 1: Setup (Verify baseline)

**Purpose**: Confirm the project builds and all existing tests pass before making any changes. Establish the pre-fix baseline.

- [X] T001 Run `swift build` from repo root and confirm zero build errors
- [X] T002 Run `swift test` from repo root and confirm all existing tests pass (baseline green state)

**Checkpoint**: Build is clean and tests are green — safe to begin fixes.

---

## Phase 2: Foundational (No blocking prerequisites)

**Purpose**: This feature has no new infrastructure, schema, or shared foundational work. All three fixes are independent changes to separate files. Proceed directly to user story phases.

*No tasks in this phase.*

---

## Phase 3: User Story 1 — Automatic background translation (Priority: P1) 🎯 MVP

**Goal**: Words captured before the vocabulary panel is opened are automatically translated within 10 seconds of app launch, with no user action. The Apple Translation session fires its callback exactly once (no infinite loop).

**Independent Test** (from quickstart.md Scenario 1):
1. Launch the app. Without opening the panel, copy `threshold`, `resilience`, `ephemeral`.
2. Wait 10 seconds.
3. Open the panel — all three rows must show French translations (no pending badge).
4. CPU usage must not stay elevated after translations complete (no loop).

### Implementation for User Story 1

- [X] T003 [US1] In `ClipboardVocab/UI/TranslationSessionHost.swift` — delete the `configuration?.invalidate()` call on line 83 inside the `.translationTask` callback body of `PersistentTranslationView`; the callback body must retain only `service.appleSession = session` and `await service.retryPendingTranslations()`

**Checkpoint**: After T003, launch the app, capture words without opening the panel, wait 10 seconds, open the panel — entries are translated. Activity Monitor shows the process is not busy-looping. User Story 1 is complete.

---

## Phase 4: User Story 2 — Reliable retry spinner (Priority: P1)

**Goal**: Tapping "Réessayer la traduction" shows a spinner for the full duration of the retry task, then stops cleanly — even if GRDB `ValueObservation` triggers view re-renders mid-retry.

**Independent Test** (from quickstart.md Scenario 2):
1. Force pending entries (e.g., unreachable fallback URL during capture).
2. Restore a valid translation endpoint.
3. Tap the retry button.
4. While retrying, copy a new word — the spinner must stay visible throughout.
5. When the last entry is translated, the spinner must disappear within 2 seconds.

### Implementation for User Story 2

- [X] T004 [US2] In `ClipboardVocab/UI/VocabularyDateGroupSection.swift` — replace the `.task(id: retryTrigger)` modifier and the `retryTrigger: Int` state variable with an explicit `Task` launched directly from the button's action closure:

  1. Remove `@State private var retryTrigger = 0` declaration.
  2. Add `@State private var currentRetryTask: Task<Void, Never>? = nil` declaration alongside the existing `isRetrying` and `retryError` state variables.
  3. Replace the `Button` action body (`retryTrigger += 1`) with:
     ```swift
     guard !isRetrying else { return }
     isRetrying = true
     retryError = nil
     currentRetryTask?.cancel()
     currentRetryTask = Task {
         do {
             _ = try await onRetryGroup()
         } catch {
             await MainActor.run { retryError = L10n.string("retry_service_error") }
         }
         await MainActor.run { isRetrying = false }
     }
     ```
  4. Remove the entire `.task(id: retryTrigger) { ... }` modifier block that follows the `Section`.

**Checkpoint**: After T004, run `swift build` (must succeed). Perform the Scenario 2 manual test — spinner appears, stays visible during a mid-retry re-render (capture a new word), and stops cleanly when done. User Story 2 is complete.

---

## Phase 5: User Story 3 — Retry uses live pending entries (Priority: P2)

**Goal**: When the retry button is tapped, only entries that are genuinely still pending at that moment are translated — not a stale snapshot from the last render cycle.

**Independent Test** (from quickstart.md Scenario 3):
1. Capture 3 words while fallback is unreachable (3 pending entries).
2. Allow background `NWPathMonitor` retry to translate 1 or 2 automatically.
3. Tap the retry button.
4. Confirm only the remaining pending entries are translated (no duplicate API calls for already-translated entries). Spinner stops promptly.

### Implementation for User Story 3

- [X] T005 [US3] In `ClipboardVocab/UI/VocabularyListView.swift` — update the `onRetryGroup` closure passed to `VocabularyDateGroupSection` (around line 82) to call `translationService.retryPendingTranslations()` instead of `translationService.retryGroup(entries: group.entries)`:

  Change:
  ```swift
  onRetryGroup: {
      return try await translationService.retryGroup(entries: group.entries)
  },
  ```
  To:
  ```swift
  onRetryGroup: {
      await translationService.retryPendingTranslations()
      return 0
  },
  ```

  Note: `retryPendingTranslations()` does not return a count and does not throw; the `onRetryGroup` closure signature (`() async throws -> Int`) is satisfied by returning `0`. If the closure signature needs updating to match, change `let onRetryGroup: () async throws -> Int` in `VocabularyDateGroupSection.swift` to `let onRetryGroup: () async -> Void` and update the call sites (`_ = try await onRetryGroup()` → `await onRetryGroup()`). Prefer the minimal change — check whether the signature change cascades before committing.

**Checkpoint**: After T005, run `swift build` (must succeed). Perform the Scenario 3 manual test — only genuinely pending entries are retranslated. User Story 3 is complete.

---

## Phase 6: Polish & Validation

**Purpose**: Regression gate, documentation update, final validation across all three stories.

- [X] T006 Run `swift build` and confirm zero errors after all three fixes are applied
- [X] T007 Run `swift test` and confirm all existing tests still pass (no regressions introduced)
- [ ] T008 [P] Run quickstart.md Scenario 1 (background translation, no loop) — confirm pass
- [ ] T009 [P] Run quickstart.md Scenario 2 (spinner terminates correctly) — confirm pass
- [ ] T010 [P] Run quickstart.md Scenario 3 (fresh pending entries used) — confirm pass
- [ ] T011 [P] Run quickstart.md Scenario 4 (misconfigured fallback: no crash, entries stay pending) — confirm pass
- [X] T012 Update `specs/004-translation-reliability/checklists/requirements.md` — mark all items as verified post-implementation

**Checkpoint**: All scenarios pass, all tests green, checklist complete. Feature is ready to merge.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: N/A — no foundational tasks
- **Phase 3 (US1 — T003)**: Can start after Phase 1 green. No dependency on US2 or US3.
- **Phase 4 (US2 — T004)**: Can start after Phase 1 green. **Independent of US1** — different file.
- **Phase 5 (US3 — T005)**: Can start after Phase 1 green. **Independent of US1 and US2** — different file.
- **Phase 6 (Polish)**: Requires T003 + T004 + T005 complete.

### User Story Dependencies

- **US1 (T003)**: `ClipboardVocab/UI/TranslationSessionHost.swift` — no dependency on US2 or US3
- **US2 (T004)**: `ClipboardVocab/UI/VocabularyDateGroupSection.swift` — no dependency on US1 or US3
- **US3 (T005)**: `ClipboardVocab/UI/VocabularyListView.swift` — no dependency on US1 or US2; caller-side change to `onRetryGroup` may depend on US2's closure signature decision (check before committing)

### Within Each User Story

- Each fix is a single task in a single file — no intra-story ordering required.
- T005 (US3) should be checked after T004 (US2) in case the `onRetryGroup` closure signature is changed in T004 (the two tasks touch related code in different files but the interface between them is the `onRetryGroup` closure type).

### Parallel Opportunities

- T003, T004, T005 can be worked on in parallel — they touch three separate files with no shared mutable state.
- T008, T009, T010, T011 (quickstart scenarios) can be run in parallel — they are independent manual test sessions.

---

## Parallel Example

```
# All three fix tasks can be started simultaneously (independent files):
T003: TranslationSessionHost.swift   — delete 1 line
T004: VocabularyDateGroupSection.swift — replace .task(id:) with explicit Task
T005: VocabularyListView.swift       — change onRetryGroup closure

# After T003 + T004 + T005 complete, all validation tasks can run in parallel:
T008: Scenario 1 (background translation)
T009: Scenario 2 (spinner)
T010: Scenario 3 (fresh snapshot)
T011: Scenario 4 (fallback misconfiguration)
```

---

## Implementation Strategy

### MVP First (User Story 1 only — T003)

1. Complete T001–T002 (baseline)
2. Apply T003 (delete `invalidate()` — 1 line change)
3. **STOP and VALIDATE**: Run Scenario 1 from quickstart.md
4. If Scenario 1 passes, the root cause of permanent pending entries is fixed

This is the highest-ROI change: one line deletion fixes the majority of reported translation failures.

### Incremental Delivery

1. T001–T002 → baseline green
2. T003 → US1 done → Scenario 1 passes (background translation works)
3. T004 → US2 done → Scenario 2 passes (spinner terminates)
4. T005 → US3 done → Scenario 3 passes (no redundant API calls)
5. T006–T012 → full validation and checklist sign-off

### Single-developer Sequence (recommended)

```
T001 → T002 → T003 → [Scenario 1 manual test] → T004 → [Scenario 2 manual test] → T005 → [Scenario 3 manual test] → T006 → T007 → T008–T011 (parallel) → T012
```

---

## Notes

- [P] tasks = different files, no shared dependencies — safe to parallelise
- Each fix is a surgical change to a single file — commit individually for clean git history
- `swift build` must pass after each task before moving to the next
- T005 has a conditional path: if the `onRetryGroup` closure signature is changed in T004, T005's implementation note about `() async throws -> Int` vs `() async -> Void` applies
- No new dependencies, no schema migrations, no new source files
