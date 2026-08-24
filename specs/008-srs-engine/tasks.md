# Tasks: SRS Engine — Spaced Repetition

**Input**: Design documents from `specs/008-srs-engine/`  
**Branch**: `008-srs-engine`  
**Prerequisites**: plan.md ✅ · spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/srs-engine.md ✅ · quickstart.md ✅

**Tests**: Required per Constitution Principle III (Gate 3). Test tasks are included for all new repository methods, the SRS algorithm, and the v4 migration.

**Organization**: Tasks map to the four user stories (US1–US4) plus shared foundational work. Each phase is independently buildable and runnable.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[USn]**: Which user story this task belongs to

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the five new SRS columns to the data model and register the v4 migration. Every subsequent phase depends on this. The `markSaved` extension and the `SRSState` / `SRSRating` / `SRSUpdate` types must also exist before any algorithm work can begin.

- [X] T001 Add top-level `SRSState` enum (`new`, `learning`, `known`, `mastered`) with `String` raw values and `Codable` conformance in `ClipboardVocab/Services/SRSEngine.swift`
- [X] T002 Add top-level `SRSRating` enum (`again`, `hard`, `good`, `easy`) — not `Codable`, no raw values — in `ClipboardVocab/Services/SRSEngine.swift`
- [X] T003 Add `SRSUpdate` value type (`struct SRSUpdate { let srsState, dueDate: String, interval, easeFactor: Double, ratingCount: Int }`) in `ClipboardVocab/Services/SRSEngine.swift`
- [X] T004 Add five new optional fields to `VocabularyEntry` (`srsState: SRSState?`, `dueDate: String?`, `interval: Double?`, `easeFactor: Double?`, `ratingCount: Int?`) and extend `CodingKeys` with five new camelCase cases in `ClipboardVocab/Models/VocabularyEntry.swift`
- [X] T005 Register migration `"v4"` in `Database.migrate()` — add five nullable columns (`srsState TEXT DEFAULT 'new'`, `dueDate TEXT DEFAULT (date('now','localtime'))`, `interval REAL DEFAULT 1.0`, `easeFactor REAL DEFAULT 2.5`, `ratingCount INTEGER DEFAULT 0`) and `CREATE INDEX idx_vocabulary_due_date ON vocabulary_entries (dueDate)` in `ClipboardVocab/Persistence/Database.swift`
- [X] T006 Extend `markSaved(id:)` in `VocabularyEntryRepository` to also set `srsState = 'new'`, `dueDate = todayString`, `interval = 1.0`, `easeFactor = 2.5`, `ratingCount = 0` in the same UPDATE statement (atomic, single transaction) in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T007 Verify `swift build` compiles successfully with model and migration changes before proceeding

**Checkpoint**: App builds. Existing tests still pass. New DB opens with five SRS columns; existing rows get their defaults. `swift test` green.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement and test `SRSEngine` (pure function) and the three new repository methods. Every user story phase depends on these being correct and tested.

**⚠️ CRITICAL**: No user story work can begin until the algorithm and repository methods are green.

- [X] T008 Implement `SRSEngine` struct with static `rate(_ entry: VocabularyEntry, rating: SRSRating) -> SRSUpdate` in `ClipboardVocab/Services/SRSEngine.swift`:
  - `again`: `newInterval = 1.0`, `newEase = max(1.3, ease - 0.2)`
  - `hard`: `newInterval = max(1.0, interval × 1.2)`, `newEase = max(1.3, ease - 0.15)`
  - `good`: `newInterval = max(1.0, interval × ease)`, ease unchanged
  - `easy`: `newInterval = max(1.0, interval × ease × 1.3)`, ease unchanged
  - `dueDate`: `Calendar.current` + `Int(newInterval.rounded())` days, formatted `YYYY-MM-DD`
  - `srsState`: derived from `newRatingCount` and `newInterval` (see derivation rule in data-model.md)
  - `ratingCount`: prior `ratingCount ?? 0` + 1
- [X] T009 Write `@Suite("SRSEngineTests")` in `Tests/Unit/SRSEngineTests.swift` using in-memory fixtures (no DB needed); cover:
  - `again` resets interval to 1.0 and decrements `easeFactor` by 0.2 (clamped at 1.3)
  - `hard` multiplies interval by 1.2 and decrements `easeFactor` by 0.15
  - `good` multiplies interval by `easeFactor`; ease unchanged
  - `easy` multiplies interval by `easeFactor × 1.3`; ease unchanged
  - minimum interval ≥ 1.0 for all ratings
  - `easeFactor` never drops below 1.3
  - first rating (ratingCount=0) → `srsState == .learning`
  - interval=6.9 → `.learning`; interval=7.0 → `.known`; interval=21.0 → `.mastered`
  - `again` from `.known` (ratingCount=5, interval=10) → `.learning` (interval=1.0, ratingCount=6)
  - `dueDate` is today + round(newInterval) in `YYYY-MM-DD` format
- [X] T010 [P] Add `fetchDueEntries() throws -> [VocabularyEntry]` to `VocabularyEntryRepository` — filters `triageStatus == 'saved'` AND `dueDate <= todayString`, orders by `dueDate` ASC; `todayString` computed via `Calendar.current` at call time in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T011 [P] Add `fetchDueCount() throws -> Int` to `VocabularyEntryRepository` — COUNT query with the same predicates as `fetchDueEntries()` in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T012 [P] Add `applyRating(id: Int64, update: SRSUpdate) throws` to `VocabularyEntryRepository` — writes all five SRS fields in a single `dbQueue.write` transaction; does NOT touch any other column; is `throws` (not `try?`) in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T013 Write `@Suite("VocabularyEntryRepositorySRSTests")` in `Tests/Unit/VocabularyEntryRepositoryTests.swift` (extend existing file or new `SRSTests` suite); use `Database(path: ":memory:")`; cover:
  - `fetchDueEntries()` returns only entries with `triageStatus == 'saved'` AND `dueDate ≤ today`
  - `fetchDueEntries()` excludes entries with `dueDate > today`
  - `fetchDueEntries()` orders overdue entries before due-today entries (oldest first)
  - `fetchDueCount()` returns the correct count after insert and after `applyRating`
  - `applyRating` writes all five fields atomically; row unchanged on DB error
  - `markSaved` sets SRS defaults: `srsState='new'`, `dueDate=today`, `interval=1.0`, `easeFactor=2.5`, `ratingCount=0`
  - newly saved entry appears in `fetchDueEntries()` immediately
- [X] T014 Write `@Suite("DatabaseMigrationV4Tests")` in `Tests/Unit/DatabaseMigrationV4Tests.swift`: verify v4 migration runs without error on a fresh in-memory DB; verify existing rows (inserted at v2 or v3 schema) get the five SRS columns with correct defaults after migration; verify no existing columns are modified
- [X] T015 Run `swift test --filter SRSEngine` and `swift test --filter VocabularyEntryRepository` and `swift test --filter DatabaseMigration` — all tests must pass

**Checkpoint**: `SRSEngine` algorithm fully tested as a pure function. Repository methods implemented and tested. Migration v4 verified. `swift test` fully green.

---

## Phase 3: US1 — Rating a Word During a Review Session (Priority: P1) 🎯 MVP

**Goal**: The SRS read/write round-trip works end-to-end. Calling `SRSEngine.rate` + `applyRating` produces correct updated fields in the database; the daily queue drops the entry within 500 ms. This is the core engine loop.

**Independent Test** (quickstart.md Scenarios 2, 3, 7):
- Rate a word **Good** → `interval` grows, `dueDate` moves forward, word leaves today's queue.
- Rate a word **Again** → `interval` resets to 1.0, `dueDate` = tomorrow.
- DB write failure (injected error) → entry unchanged in DB, error returned to caller.

### Implementation — US1

- [X] T016 [US1] Wire the end-to-end rating path in a new helper (or document it in the contract as the caller's responsibility): `let update = SRSEngine.rate(entry, rating: .good)` → `try repository.applyRating(id: entry.id!, update: update)` — ensure this sequence is exercised in an integration test in `Tests/Integration/CaptureToStorageTests.swift` (extend existing suite)
- [X] T017 [US1] Add integration test `ratingRoundTrip`: save an Inbox entry (markSaved), assert it appears in `fetchDueEntries()`, call `SRSEngine.rate` + `applyRating` with `.good`, assert entry no longer in `fetchDueEntries()`, assert new `dueDate` == today + round(2.5) days in `Tests/Integration/CaptureToStorageTests.swift`
- [X] T018 [US1] Add integration test `againRatingResetsInterval`: entry with `interval=10.0`, rate `again` → assert `interval == 1.0`, `dueDate == tomorrow`, `srsState == .learning` in `Tests/Integration/CaptureToStorageTests.swift`
- [X] T019 [US1] Add integration test `writeFailureDoesNotMutateEntry`: pass a closed `DatabaseQueue` to `applyRating` → assert it throws, assert original SRS fields unchanged in `Tests/Unit/VocabularyEntryRepositoryTests.swift`
- [X] T020 [US1] Run `swift test --filter CaptureToStorage` and `swift test --filter VocabularyEntryRepository` — all new tests must pass

**Checkpoint (US1 done)**: Rating path fully exercised in integration tests. Write failure handling confirmed. `swift test` fully green.

---

## Phase 4: US2 — Seeing Today's Review Queue (Priority: P1)

**Goal**: `fetchDueEntries()` returns exactly the right entries (overdue + due-today), ordered correctly. The count is reactive via `ValueObservation`. Epic 4's Learn/Review views have a correct, observable data source.

**Independent Test** (quickstart.md Scenario 5):
- Insert entries with `dueDate = yesterday`, `today`, `tomorrow` → only first two returned, oldest first.
- After `applyRating` moves a word to a future date, it disappears from the queue.
- `fetchDueCount()` matches `fetchDueEntries().count` at all times.

### Implementation — US2

- [X] T021 [P] [US2] Add `ValueObservation.tracking { db in try VocabularyEntry.filter(...).filter(...).order(...).fetchAll(db) }` daily queue observation as a documented pattern in `specs/008-srs-engine/contracts/srs-engine.md` — confirm the contract example (C-30 through C-37) matches the actual `fetchDueEntries` implementation; update the contract if any discrepancy is found
- [X] T022 [P] [US2] Add `ValueObservation.tracking { db in try VocabularyEntry.filter(...).filter(...).fetchCount(db) }` queue-count observation as a documented pattern alongside T021; this is the source for `DailyProgressBar` (Epic 1) — add a code comment in `VocabularyEntryRepository` pointing to the pattern in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T023 [US2] Write `@Suite("DailyQueueObservationTests")` in `Tests/Unit/VocabularyEntryRepositoryTests.swift`: use `ValueObservation.values(in: dbQueue)` with `AsyncSequence`; insert overdue entry, assert it fires; call `applyRating` to move entry to future, assert queue count drops; insert due-today entry, assert it appears; sleep 100 ms after each write for observation to settle
- [X] T024 [US2] Run `swift test --filter DailyQueueObservation` — must pass; run `swift test` (full suite) — all green

**Checkpoint (US2 done)**: Daily queue reactive observation confirmed. Count observation works. Order (overdue-first) verified. `swift test` fully green.

---

## Phase 5: US3 — A Newly Saved Word Enters the SRS Pipeline (Priority: P2)

**Goal**: When the user saves a word from the Inbox, the `markSaved` update atomically sets all SRS defaults. The word immediately appears in `fetchDueEntries()` with `srsState = .new`, `dueDate = today`, `interval = 1.0`.

**Independent Test** (quickstart.md Scenario 1):
- Save a word via `markSaved` → assert `srsState == .new`, `dueDate == today`, `ratingCount == 0`.
- Assert it appears in `fetchDueEntries()` without any additional call.

### Implementation — US3

- [X] T025 [US3] Verify the `markSaved(id:)` implementation from T006 is correct: check the UPDATE SQL sets all six fields atomically (`triageStatus`, `srsState`, `dueDate`, `interval`, `easeFactor`, `ratingCount`) in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T026 [US3] Add targeted unit test `markSavedSetsSRSDefaults` in `Tests/Unit/VocabularyEntryRepositoryTests.swift`: insert an unreviewed entry, call `markSaved`, fetch the row, assert all five SRS fields match their defaults (`srsState = .new`, `dueDate = today`, `interval = 1.0`, `easeFactor = 2.5`, `ratingCount = 0`)
- [X] T027 [US3] Add unit test `newlySavedEntryAppearsInQueue` in `Tests/Unit/VocabularyEntryRepositoryTests.swift`: insert entry, `markSaved`, call `fetchDueEntries()`, assert entry is present in the result
- [X] T028 [US3] Run `swift test --filter VocabularyEntryRepository` — all tests including T026 and T027 must pass

**Checkpoint (US3 done)**: Inbox-to-SRS pipeline seamless. Every saved word enters the daily queue on the same day. `swift test` fully green.

---

## Phase 6: US4 — SRS State Progresses Through the Lifecycle (Priority: P2)

**Goal**: A word advances from `.new` → `.learning` → `.known` → `.mastered` through a sequence of positive ratings at the correct interval thresholds. `Again` from any non-new state reverts to `.learning`.

**Independent Test** (quickstart.md Scenario 4):
- Simulate 4× `Good` from initial state: verify state after each rating matches `.learning`, `.learning`, `.known`, `.mastered`.
- Rate a `.mastered` word with `Again` → state = `.learning`, `interval = 1.0`.

### Implementation — US4

- [X] T029 [US4] Add `@Suite("SRSLifecycleTests")` in `Tests/Unit/SRSEngineTests.swift` simulating the full progression sequence (no DB needed — pure `SRSEngine.rate` calls chained):
  - Initial entry: `interval=1.0, easeFactor=2.5, ratingCount=0`
  - Rate `good` → `ratingCount=1, interval=2.5, srsState=.learning`
  - Rate `good` → `ratingCount=2, interval=6.25, srsState=.learning`
  - Rate `good` → `ratingCount=3, interval=15.625, srsState=.known`
  - Rate `good` → `ratingCount=4, interval=39.0625, srsState=.mastered`
  - From mastered: rate `again` → `ratingCount=5, interval=1.0, srsState=.learning`
- [X] T030 [US4] Add boundary tests in `Tests/Unit/SRSEngineTests.swift`:
  - `interval=6.99` → `.learning`; `interval=7.0` → `.known`; `interval=20.99` → `.known`; `interval=21.0` → `.mastered`
  - `ratingCount=0` always → `.new` regardless of interval value
- [X] T031 [US4] Run `swift test --filter SRSLifecycle` and `swift test --filter SRSEngine` — all tests must pass

**Checkpoint (US4 done)**: Full state machine verified in unit tests. All four user stories are fully tested. `swift test` fully green.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Persistence verification, L10n, and final integration sweep. Runs after all stories are individually confirmed working.

- [X] T032 Write `@Suite("SRSPersistenceTests")` in `Tests/Unit/VocabularyEntryRepositoryTests.swift`: create DB, apply several ratings, close `DatabaseQueue`, re-open from the same path (use a temp file path, not `:memory:`), re-fetch entries, assert SRS fields are identical to pre-close values — covers success criterion 5 (survives restart)
- [X] T033 [P] Add L10n key stubs for any user-visible SRS strings that will be needed by Epic 4 views: e.g. `"srs_rating_again"`, `"srs_rating_hard"`, `"srs_rating_good"`, `"srs_rating_easy"`, `"srs_state_new"`, `"srs_state_learning"`, `"srs_state_known"`, `"srs_state_mastered"` in `ClipboardVocab/Resources/Localizable.strings`
- [X] T034 [P] Add a `// MARK: - SRS` section header comment and inline doc-comments to `SRSEngine.rate(_:rating:)` explaining the SM-2 formula for each case; include the state-derivation rule as a comment in `ClipboardVocab/Services/SRSEngine.swift`
- [X] T035 Run `swift test` (full suite) — all tests must pass with zero failures; run `swift build` — zero warnings related to this feature
- [ ] T036 Manually validate quickstart.md Scenarios 1–8 in sequence to confirm end-to-end integration (requires Epic 2 Inbox Save flow to be in place for Scenarios 1 and 8)

**Checkpoint**: Complete SRS engine working end-to-end. Persistence confirmed across restart. All strings localised. Full `swift test` suite green.

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Schema + Types + markSaved extension)
    └── Phase 2 (SRSEngine + Repository methods + Tests)  ← BLOCKS all story phases
            ├── Phase 3 (US1 — Rating round-trip)         ← MVP
            │       └── Phase 4 (US2 — Queue reactivity)  ← builds on Phase 3 data
            ├── Phase 5 (US3 — Inbox→SRS pipeline)        ← independent of Phase 3–4
            └── Phase 6 (US4 — State lifecycle)           ← pure function, independent
                        └── Phase 7 (Polish & final sweep) ← after all stories
```

- **US3 (Inbox pipeline)** and **US4 (Lifecycle)** depend only on Phase 2 and can be developed in parallel with US1–US2.
- **US2 (Queue reactivity)** depends on US1 being complete (it observes the result of a rating write).
- **Phase 7 (Persistence)** must run last — it requires all write paths to exist.

### Parallel Opportunities

- T001–T003 (`SRSState`, `SRSRating`, `SRSUpdate` type definitions) can be written in parallel — all in the same file but logically independent.
- T009 (`SRSEngineTests`) can be drafted in parallel with T008 (implementation) using the algorithm spec as the source of truth — the tests define the contract.
- T010–T012 (repository method stubs) can all be added in parallel — they are additions to the same file with no internal dependencies.
- T021–T022 (observation pattern documentation) can run in parallel with T023 (observation tests).
- T032–T034 (Phase 7) can all run in parallel — different files, no ordering constraint.

---

## Implementation Strategy

### MVP (US1 only — Phases 1–3)

1. Complete Phase 1 (Schema, types, `markSaved` extension)
2. Complete Phase 2 (Algorithm + repository + tests)
3. Complete Phase 3 (US1 — rating round-trip integration test)
4. **STOP and VALIDATE**: `swift test` green; quickstart.md Scenarios 2, 3, 7 pass
5. The engine is usable: Epic 4 can wire up its UI against a fully tested, correct SRS backend

### Full Feature (Phases 1–7)

1. MVP scope above
2. Phase 4: Queue reactivity tests (US2)
3. Phase 5: Inbox pipeline tests (US3)
4. Phase 6: Lifecycle boundary tests (US4)
5. Phase 7: Persistence + L10n + final sweep
6. Final `swift test` (full suite) + quickstart.md all 8 scenarios

---

## Notes

- `[P]` tasks = different files or logically independent additions with no ordering constraint within the phase
- `[USn]` label maps each task to the user story for traceability
- Use `Database(path: ":memory:")` in every test `makeRepo()` helper — never a tmp file path (except T032 which explicitly tests persistence across restart)
- `applyRating` is `throws` — callers in Epic 4 must `catch` and apply the re-queue behaviour; never call with `try?` at the UI layer
- `SRSEngine.rate` is NOT `throws` — it is a pure function; never add `try` at call sites
- GRDB column keys: `Column("srsState")`, `Column("dueDate")`, `Column("interval")`, `Column("easeFactor")`, `Column("ratingCount")` — camelCase matching the SQL column names exactly (see AGENTS.md GRDB rule)
- `ValueObservation` fires automatically after every `applyRating` write; no `NotificationCenter` needed
- `todayString` must be computed at call time via `Calendar.current` — never hardcoded or cached across midnight
- The `SRSEngine` struct must remain a pure function: it does not import `Foundation` I/O, does not access `dbQueue`, and has no `@MainActor` annotation
