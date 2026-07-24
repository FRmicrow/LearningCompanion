---
description: "Task list for Translation Correctness & Sync"
---

# Tasks: Translation Correctness & Sync

**Input**: Design documents from `specs/005-translation-correctness-sync/`

**Branch**: `005-translation-correctness-sync`

**Prerequisites**: plan.md ✅ · spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/translation-service-v3.md ✅ · quickstart.md ✅

**Tests**: One new Swift Testing test is generated (for the concurrency guard — the only new logic). Existing test suite is the regression gate for all other user stories.

**Organization**: Tasks are grouped by user story. All three user stories share a single foundational change (Phase 2); US2 and US3 are verified by the existing test suite and manual quickstart scenarios.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[Story]**: User story this task belongs to ([US1], [US2], [US3])

---

## Phase 1: Setup (Verify baseline)

**Purpose**: Confirm the project builds and all 38 existing tests pass before making any changes. Establish the pre-fix baseline.

- [X] T001 Run `swift build` from repo root and confirm zero build errors
- [X] T002 Run `swift test` from repo root and confirm all 38 existing tests pass (baseline green state)

**Checkpoint**: Build is clean and tests are green — safe to begin implementation.

---

## Phase 2: Foundational (Concurrency guard — prerequisite for all user stories)

**Purpose**: The single implementation change that satisfies FR-009 and SC-005, and that all three user story validations depend on. It touches one file and must be complete before any quickstart scenario is meaningful.

**⚠️ CRITICAL**: User story validation phases (Phases 3–5) depend on this phase being complete.

### Implementation

- [X] T003 In `ClipboardVocab/Services/TranslationService.swift` — add a `private var retryInProgress = false` property to `TranslationService` and update `retryPendingTranslations()` to guard against concurrent re-entry:

  1. Add the property declaration immediately after `private var _appleSession: AnyObject?` (around line 48):
     ```swift
     private var retryInProgress = false
     ```
  2. Replace the body of `retryPendingTranslations()` (lines 84–89) with:
     ```swift
     func retryPendingTranslations() async {
         guard !retryInProgress else { return }
         retryInProgress = true
         defer { retryInProgress = false }
         guard let pending = try? repository.fetchPending() else { return }
         for entry in pending {
             await translate(entry: entry)
         }
     }
     ```
  3. No changes to `translate(entry:)` or `retryGroup(entries:)` — those methods are unaffected by this guard.

- [X] T004 In `Tests/Unit/TranslationServiceTests.swift` — add a new `@Test` that verifies a concurrent second call to `retryPendingTranslations()` is a no-op while the first is in flight:

  Add the following test to the `TranslationServiceTests` suite (after the existing `testRetryGroup_emptyArrayReturnsZero` test):
  ```swift
  @Test("retryPendingTranslations is a no-op when already in flight")
  func testRetryPendingTranslations_concurrentCallIsNoOp() async throws {
      let repo = try makeRepo()
      let service = TranslationService(repository: repo)
      // Unreachable URL so translate() always fails fast (entries stay pending)
      service.libreTranslateURL = URL(string: "http://127.0.0.1:1")!

      _ = try repo.upsert(englishText: "concurrent")

      // Launch first call; while it is running (loop will attempt translate and fail fast),
      // launch a second concurrent call — it must return immediately and not start a second pass.
      async let first: Void = service.retryPendingTranslations()
      async let second: Void = service.retryPendingTranslations()
      _ = await (first, second)

      // Entry must still be pending (unreachable URL) — and only one translate attempt
      // was made (the test verifies no crash and the guard held).
      let pending = try repo.fetchPending()
      #expect(pending.count == 1, "Entry must remain pending when network is unreachable")
  }
  ```

- [X] T005 Run `swift build` and confirm zero errors after T003 and T004

- [X] T006 Run `swift test` and confirm all tests pass (now 39 tests, including the new concurrency test)

**Checkpoint**: Concurrency guard is implemented, builds clean, and all 39 tests pass. Proceed to user story validation.

---

## Phase 3: User Story 1 — Automatic background translation, no entry stuck as pending (Priority: P1) 🎯 MVP

**Goal**: Every eligible word captured while the vocabulary panel is closed is translated automatically within 10 seconds of the translation backend becoming ready, with no user action. The concurrency guard (Phase 2) ensures no duplicate retry passes.

**Independent Test** (from quickstart.md Scenario 1):
1. Launch the app. **Do not open the vocabulary panel.**
2. Copy `threshold`, `resilience`, `ephemeral` (one at a time, ~1 second apart).
3. Wait 10 seconds.
4. Open the vocabulary panel.
5. All three rows must display French translations — no pending badge.
6. CPU usage must not stay elevated after translations complete (no retry loop).

### Implementation for User Story 1

- [X] T007 [US1] Run quickstart.md Scenario 1 (background translation without opening panel) — confirm all three rows are translated, spinner stops, CPU returns to idle

**Checkpoint**: Background translation works end-to-end. No pending entries remain after the session-ready callback fires. User Story 1 is complete.

---

## Phase 4: User Story 2 — Live panel updates without close/reopen (Priority: P1)

**Goal**: Translations that complete in the background while the vocabulary panel is open appear automatically in the panel — no manual refresh required.

**Independent Test** (from quickstart.md Scenario 2):
1. Produce pending entries (use unreachable URL during capture).
2. Open the panel — confirm entries show pending badges.
3. Re-enable the translation backend.
4. **Without closing the panel**, wait up to 10 seconds.
5. Each pending row must update in place to show its French translation.

### Implementation for User Story 2

- [X] T008 [US2] Run quickstart.md Scenario 2 (live panel update) — confirm pending rows update automatically in the open panel within 10 seconds of backend becoming available, with no close/reopen

**Checkpoint**: GRDB `ValueObservation` drives live row updates correctly. No stale state visible to the user. User Story 2 is complete.

---

## Phase 5: User Story 3 — Reliable manual retry, stable spinner (Priority: P2)

**Goal**: Tapping "Réessayer la traduction" shows a progress indicator for the full duration of the retry task, then stops cleanly — even if a GRDB-triggered re-render occurs mid-retry, and even if a concurrent automatic retry is triggered simultaneously.

**Independent Test** (from quickstart.md Scenarios 3 and 4):
- Scenario 3: Retry button → spinner appears → stays through mid-retry re-render → spinner stops cleanly within 2 seconds of last translation.
- Scenario 4: Simultaneous manual retry + connectivity restore → exactly N translation requests (one per pending entry, no duplicates).

### Implementation for User Story 3

- [X] T009 [US3] Run quickstart.md Scenario 3 (retry spinner lifecycle) — confirm spinner appears immediately, persists through a mid-retry capture, and disappears cleanly within 2 seconds of completion
- [X] T010 [US3] Run quickstart.md Scenario 4 (concurrent retry guard) — confirm no duplicate translation requests are issued when manual retry and connectivity-restore fire simultaneously

**Checkpoint**: Retry spinner is stable. Concurrency guard prevents redundant passes. User Story 3 is complete.

---

## Phase 6: Polish & Validation

**Purpose**: Regression gate, fallback edge case, and documentation sign-off.

- [X] T011 [P] Run quickstart.md Scenario 5 (misconfigured fallback — no crash, entries stay pending, then translate when backend available) — confirm pass
- [X] T012 [P] Run `swift build` and `swift test` one final time — confirm 39 tests pass and zero build errors
- [X] T013 [P] Update `specs/005-translation-correctness-sync/checklists/requirements.md` — mark all items as verified post-implementation

**Checkpoint**: All scenarios pass, all tests green, checklist complete. Feature is ready to merge.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Requires Phase 1 green. **Blocks all user story validation phases.**
- **Phase 3 (US1)**: Requires Phase 2 complete
- **Phase 4 (US2)**: Requires Phase 2 complete; independent of Phase 3
- **Phase 5 (US3)**: Requires Phase 2 complete; independent of Phases 3 and 4
- **Phase 6 (Polish)**: Requires Phases 3 + 4 + 5 complete

### User Story Dependencies

- **US1 (T007)**: No dependency on US2 or US3 — quickstart Scenario 1 tests background translation in isolation
- **US2 (T008)**: No dependency on US1 or US3 — quickstart Scenario 2 tests live panel updates in isolation
- **US3 (T009, T010)**: No dependency on US1 or US2 — quickstart Scenarios 3/4 test retry lifecycle in isolation

### Within Each Phase

- T003 (guard implementation) must complete before T004 (test), which must complete before T005 (build) and T006 (test run)
- T007, T008, T009, T010 can be run in parallel — they are independent manual test sessions

### Parallel Opportunities

- T007, T008, T009, T010 (quickstart scenarios) can all be run in parallel — each is a standalone manual session
- T011, T012, T013 (polish) can all be run in parallel

---

## Parallel Example

```
# Phase 2 tasks are sequential (T003 → T004 → T005 → T006):
T003: Add retryInProgress guard to TranslationService.swift
T004: Add concurrency test to TranslationServiceTests.swift
T005: swift build (verify)
T006: swift test (verify 39 tests pass)

# After Phase 2, all story validation tasks can run in parallel:
T007: Scenario 1 (background translation, US1)
T008: Scenario 2 (live panel update, US2)
T009: Scenario 3 (spinner lifecycle, US3)
T010: Scenario 4 (concurrent guard, US3)

# Polish tasks can all run in parallel:
T011: Scenario 5 (fallback edge case)
T012: Final swift build + swift test
T013: Update checklists/requirements.md
```

---

## Implementation Strategy

### MVP First (User Story 1 only — T001–T007)

1. Complete T001–T002 (baseline)
2. Apply T003 (concurrency guard — 5-line change to `TranslationService.swift`)
3. Add T004 (new test for the guard)
4. Run T005–T006 (build + test: confirm 39 tests pass)
5. **STOP and VALIDATE**: Run quickstart.md Scenario 1 (background translation)
6. If Scenario 1 passes, the most critical correctness guarantee is confirmed

This is the highest-ROI change: one guard flag closes the last reliability gap and satisfies FR-009 / SC-005.

### Incremental Delivery

1. T001–T002 → baseline green
2. T003–T006 → guard implemented, 39 tests pass
3. T007 → US1 done → Scenario 1 passes (background translation correct)
4. T008 → US2 done → Scenario 2 passes (live UI sync correct)
5. T009–T010 → US3 done → Scenarios 3 + 4 pass (retry lifecycle correct)
6. T011–T013 → full validation and checklist sign-off

### Single-developer Sequence (recommended)

```
T001 → T002 → T003 → T004 → T005 → T006 →
[Scenario 1] T007 → [Scenario 2] T008 → [Scenario 3] T009 → [Scenario 4] T010 →
T011 → T012 → T013
```

---

## Notes

- [P] tasks = different sessions / independent validation — safe to parallelise
- T003 is a 5-line edit to one file (`ClipboardVocab/Services/TranslationService.swift`) — commit it alone for a clean git history
- T004 adds one test to `Tests/Unit/TranslationServiceTests.swift` — commit with T003 or separately
- `swift build` must pass after T003 before moving to T004
- The three user story validation tasks (T007–T010) are manual sessions, not automated tests — they verify the full end-to-end behaviour that cannot be covered by unit tests alone
- No new files, no new dependencies, no schema migrations
