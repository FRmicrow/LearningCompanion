# Tasks: Inbox Word Management & Learn Session Control

**Input**: Design documents from `specs/010-inbox-word-management/`
**Branch**: `010-inbox-word-management`
**Prerequisites**: spec.md ✅ · plan.md ✅ · research.md ✅ · data-model.md ✅ · contracts/inbox-word-management.md ✅ · quickstart.md ✅

**Tests**: Required (project convention, matching Epic 4 pattern). Test tasks are included for all new repository methods, the v6 migration, sampling logic, and mastery state transitions.

**Organization**: Tasks map to the four user stories (US1–US4) plus shared foundational work. Each phase is independently buildable and runnable.

> **Path convention**: All new Swift source files live under `ClipboardVocab/UI/` (views) or `ClipboardVocab/Models/` (value types) or `ClipboardVocab/Persistence/` (repository/DB). The SPM target uses recursive discovery under `ClipboardVocab/` — any file placed there is automatically included. Test files live under `Tests/Unit/`.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[USn]**: Which user story this task belongs to

---

## Phase 1: Setup (Schema + Model Changes)

**Purpose**: Add the `isMastered` column via migration `v6`, update `VocabularyEntry`, update `FocusSession`, update the two existing queue queries. Every subsequent phase depends on this compiling and migrating cleanly.

- [X] T001 Add `isMastered: Bool` field (defaulting to `false` on init) to `VocabularyEntry` and extend `CodingKeys` with `case isMastered = "isMastered"` in `ClipboardVocab/Models/VocabularyEntry.swift`
- [X] T00- [X] T002 Register migration `"v6"` in `Database.migrate()` — executes `ALTER TABLE vocabulary_entries ADD COLUMN isMastered INTEGER NOT NULL DEFAULT 0` — immediately after the `"v5"` registration in `ClipboardVocab/Persistence/Database.swift`
- [X] T00- [X] T003 Update `fetchDueEntries()` to add `.filter(Column("isMastered") == false)` alongside the existing `triageStatus` and `dueDate` filters in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T00- [X] T004 Update `fetchDueCount()` to add `.filter(Column("isMastered") == false)` alongside the existing filters in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T00- [X] T005 Add `isOnDemand: Bool` as a `let` (immutable) field to `FocusSession`; update the sole `FocusSession` initialisation call in `LearnView.startSession()` to pass `isOnDemand: false` in `ClipboardVocab/Models/FocusSession.swift` and `ClipboardVocab/UI/LearnView.swift`
- [X] T00- [X] T006 Verify `swift build` compiles with all model, migration, and session changes — zero errors, zero new warnings — before proceeding

**Checkpoint**: App builds. Existing `swift test` suite still green (T001–T005 are additive; all prior tests pass). Migration `v6` opens without error on a fresh DB.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement and test the three new repository methods (`fetchLearnPool`, `markMastered`, `deleteAll`), verify migration `v6`, and add all new L10n strings. Every user story phase depends on these being correct and tested.

**⚠️ CRITICAL**: No user story work can begin until these tests are green.

- [X] T00- [X] T007 Add `func fetchLearnPool() throws -> [VocabularyEntry]` to `VocabularyEntryRepository` — filters `triageStatus = 'saved'` AND `isMastered = false`, orders by `dueDate` ascending — in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T00- [X] T008 Add `func markMastered(id: Int64) throws` to `VocabularyEntryRepository` — single `dbQueue.write` UPDATE: `SET isMastered = 1 WHERE id = ?` — does NOT touch any SRS column, `triageStatus`, `difficultyLabel`, or `lastReviewedDate` — in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T00- [X] T009 Add `func deleteAll(ids: [Int64]) throws` to `VocabularyEntryRepository` — single `dbQueue.write` using `VocabularyEntry.filter(ids: ids).deleteAll(db)`; early-return no-op when `ids.isEmpty` — in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T0- [X] T010 [P] Write `@Suite("DatabaseMigrationV6Tests")` in `Tests/Unit/DatabaseMigrationV6Tests.swift`; use `Database(path: ":memory:")`; cover:
  - Migration `v6` runs without error on a DB at `v5`
  - Existing rows have `isMastered = false` after migration
  - No existing column (including all `v5` annotation columns) is modified or removed
  - A freshly inserted entry via `upsert(englishText:)` has `isMastered == false`
- [X] T0- [X] T011 [P] Write `@Suite("VocabularyEntryRepositoryMasteryTests")` in `Tests/Unit/VocabularyEntryRepositoryTests.swift` (extend existing file); use `Database(path: ":memory:")`; cover:
  - `markMastered(id:)` sets `isMastered = true` and does not change `triageStatus`, `dueDate`, `srsState`, `difficultyLabel`, or any other field
  - `fetchDueEntries()` excludes a mastered entry (saved, `dueDate ≤ today`, but `isMastered = true`)
  - `fetchDueEntries()` includes a saved, non-mastered entry with `dueDate ≤ today`
  - `fetchDueCount()` returns one less after `markMastered` for a previously-counted entry
  - `fetchLearnPool()` includes saved, non-mastered entries with any `dueDate` (past and future)
  - `fetchLearnPool()` excludes mastered entries
  - `fetchLearnPool()` orders results by `dueDate` ascending
  - `deleteAll(ids:)` removes exactly the specified entries in a single write; non-specified entries remain
  - `deleteAll(ids: [])` is a no-op — entry count unchanged
- [X] T0- [X] T012 Add new L10n keys for this feature in `ClipboardVocab/Resources/Localizable.strings`:
  - `"inbox_select_button"` = `"Select"`
  - `"inbox_cancel_button"` = `"Cancel"`
  - `"inbox_delete_selected_button"` = `"Delete Selected"`
  - `"inbox_add_to_learn_button"` = `"Add to Learn"`
  - `"session_restart_button"` = `"Restart Session"`
  - `"entry_mastered_label"` = `"Mastered"`
- [X] T0- [X] T013 Run `swift test --filter DatabaseMigrationV6` and `swift test --filter VocabularyEntryRepository` — all tests must pass; run `swift test` (full suite) — all green

**Checkpoint**: `fetchLearnPool`, `markMastered`, `deleteAll` implemented and tested. Migration `v6` verified. `fetchDueEntries` / `fetchDueCount` mastery exclusion confirmed. Full `swift test` suite green.

---

## Phase 3: US1 — Bulk Delete from Inbox (Priority: P1) 🎯 MVP

**Goal**: The Inbox tab gains a Select button that activates per-row checkboxes. The user can select any subset of words and delete them all in one tap. Cancel exits selection mode with no writes.

**Independent Test** (quickstart.md Scenarios 4, 5):
- Enter selection mode → checkboxes visible, Delete Selected disabled.
- Select 3 of 5 words → Delete Selected enabled → tap → exactly those 3 words are gone, 2 remain (ValueObservation fires once).
- Select 0 → Delete Selected stays disabled.
- Cancel → no write, all words still present.

### Implementation — US1

- [X] T0- [X] T014 [US1] Add `@State private var isSelecting: Bool = false` and `@State private var selectedIDs: Set<Int64> = []` to `VocabularyListView` in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T0- [X] T015 [US1] Add a toolbar/header to the Inbox list in `VocabularyListView` that shows a **Select** button when `isSelecting == false` and a **Cancel** button when `isSelecting == true`; tapping Select sets `isSelecting = true`; tapping Cancel resets both `isSelecting = false` and `selectedIDs = []` — in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T0- [X] T016 [US1] When `isSelecting == true`, render a checkbox overlay (or leading `Label`/`Toggle`) on each Inbox list row; tapping a row in selection mode toggles the row's `id` in `selectedIDs` (add if absent, remove if present) rather than triggering the normal row action — in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T0- [X] T017 [US1] Add **Delete Selected** button to the selection toolbar in `VocabularyListView`; button is `.disabled(selectedIDs.isEmpty)`; action: `Task { try? repository.deleteAll(ids: Array(selectedIDs)) }`, then reset `isSelecting = false` and `selectedIDs = []` — in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T0- [X] T018 [US1] Write `@Suite("InboxSelectionTests")` in `Tests/Unit/InboxSelectionTests.swift`; use `Database(path: ":memory:")`; cover the repository side of the delete flow:
  - Insert 5 entries, `deleteAll` with 3 IDs → 2 remain
  - `deleteAll` with an empty array → all 5 remain, no throw
  - `deleteAll` with a non-existent ID → no error thrown, other rows unaffected
- [X] T0- [X] T019 [US1] Run `swift test --filter InboxSelection` — all must pass; run `swift build` — zero errors

**Checkpoint (US1 done)**: Selection mode activates/deactivates correctly. Bulk delete removes exactly the selected rows. ValueObservation fires once per batch delete. `swift test` green.

---

## Phase 4: US4 — Easy Rating = Mastered (Priority: P1)

**Goal**: Rating a word Easy in a Learn session sets `isMastered = true`, permanently excluding it from all future queues. The word remains visible in the vocabulary list with a "Mastered" label.

**Independent Test** (quickstart.md Scenarios 8, 9):
- Rate a word Easy → `isMastered = true` in the DB → word absent from `fetchDueEntries()` and `fetchLearnPool()` → word present in `fetchAll()` with `isMastered == true`.

### Implementation — US4

- [X] T0- [X] T020 [US4] In `LearnView.submitRating(card:rating:)`, add a mastery write after a successful `applyRating` write when `rating == .easy`: call `try repository.markMastered(id: card.id!)` inside the existing `do` block (after `applyRating`, before `session?.recordRating` and `session?.advance`); on `markMastered` failure, log the error but do NOT show a user-visible indicator and do NOT abort session advancement — in `ClipboardVocab/UI/LearnView.swift`
- [X] T0- [X] T021 [US4] In `VocabularyEntryRow` (or whichever view renders a row in the vocabulary list), show a "Mastered" badge/label when `entry.isMastered == true`; use `L10n.string("entry_mastered_label")`; place it alongside the existing row content (e.g., as a trailing label in `.foregroundStyle(.secondary)`) — in the appropriate row view file under `ClipboardVocab/UI/`
- [X] T0- [X] T022 [P] [US4] Write `@Suite("MasteryTests")` in `Tests/Unit/MasteryTests.swift`; use `Database(path: ":memory:")`; cover:
  - Save an entry (`markSaved`), assert it appears in `fetchDueEntries()`, call `markMastered(id:)`, assert it NO LONGER appears in `fetchDueEntries()`
  - After `markMastered`, entry is absent from `fetchLearnPool()`
  - After `markMastered`, entry IS present in `fetchAll()` with `isMastered == true`
  - `markMastered` is idempotent: calling it twice does not throw and `isMastered` remains `true`
  - A second `markMastered` call does not touch any other field (re-fetch and check `triageStatus`, `dueDate` unchanged)
- [X] T0- [X] T023 [US4] Run `swift test --filter MasteryTests` — all must pass; run `swift build` — zero errors; manually confirm: rate a card Easy in a Learn session → the word no longer appears in the next session queue

**Checkpoint (US4 done)**: Easy rating permanently retires a word from all future SRS and Learn queues. Mastered badge visible in vocabulary list. `swift test` green.

---

## Phase 5: US2 — Promote Inbox Words to Learn (Priority: P1)

**Goal**: In selection mode, an **Add to Learn** button constructs an on-demand `FocusSession` from the selected words and navigates to the Learn tab. The promoted words stay in the Inbox.

**Independent Test** (quickstart.md Scenario 2 in `quickstart.md` manual smoke test):
- Select 2 Inbox words → Add to Learn → Learn tab opens → session contains exactly those 2 words → Inbox still shows both words after.

### Implementation — US2

- [X] T0- [X] T024 [US2] Expose a `session` binding and an `onNavigateToLearn` callback on `VocabularyListView` so the parent can be notified to switch tabs:
  - Add `@Binding var session: FocusSession?` parameter to `VocabularyListView`'s init in `ClipboardVocab/UI/VocabularyListView.swift`
  - Add `var onNavigateToLearn: (() -> Void)?` parameter to `VocabularyListView`'s init
  - Update the call site in `VocabularySidebarView.contentForTab(.inbox)` to pass `session: $focusSession` and `onNavigateToLearn: { selectedTab = .learn }` in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [X] T0- [X] T025 [US2] Add **Add to Learn** button to the selection toolbar in `VocabularyListView`; button is `.disabled(selectedIDs.isEmpty)`; action:
  - Collect selected entries: `let selected = entries.filter { selectedIDs.contains($0.id ?? -1) }`
  - Construct: `session = FocusSession(totalCards: selected.count, cards: selected, ratedCount: 0, tally: .init(), failedCardIDs: [], isOnDemand: true)`
  - Call `onNavigateToLearn?()`
  - Reset `isSelecting = false` and `selectedIDs = []`
  - Note: promoted words are NOT deleted from the Inbox (no `deleteAll` call here)
  — in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T0- [X] T026 [US2] Run `swift build` — zero errors; manually verify: select 2 Inbox words → Add to Learn → Learn tab opens with a 2-card session; Inbox still shows both words

**Checkpoint (US2 done)**: On-demand Learn session constructed from Inbox selection. Tab switches to Learn automatically. Promoted words remain in Inbox. `swift test` still green.

---

## Phase 6: US3 — Restart Learn Session (Priority: P2)

**Goal**: A **Restart Session** button on the completion screen and in the Learn idle state starts a new session from the full Learn-eligible pool. If the pool exceeds 20 words, exactly 20 are randomly sampled using `Array.shuffled()`.

**Independent Test** (quickstart.md Scenarios 6, 7):
- Pool ≤ 20: restart → session contains all pool entries.
- Pool > 20: restart → session contains exactly 20 randomly sampled entries.
- Pool empty (all mastered): restart → empty state shown, no session started.

### Implementation — US3

- [X] T0- [X] T027 [US3] Implement `restartSession()` action in `LearnView`:
  - `Task { let pool = (try? repository.fetchLearnPool()) ?? []; await MainActor.run { if pool.isEmpty { /* showCompletion stays true or session stays nil */ } else { let cards = pool.count > 20 ? Array(pool.shuffled().prefix(20)) : pool; session = FocusSession(totalCards: cards.count, cards: cards, ratedCount: 0, tally: .init(), failedCardIDs: [], isOnDemand: false); showCompletion = false } } }`
  - in `ClipboardVocab/UI/LearnView.swift`
- [X] T0- [X] T028 [US3] Add **Restart Session** button to `SessionCompletionView` alongside the existing **Done** button; button calls an `onRestart: (() -> Void)?` callback passed in from `LearnView`; the callback invokes `restartSession()` — in `ClipboardVocab/UI/SessionCompletionView.swift` and `ClipboardVocab/UI/LearnView.swift`
- [X] T0- [X] T029 [P] [US3] Write `@Suite("LearnSessionRestartTests")` in `Tests/Unit/LearnSessionRestartTests.swift`; use in-memory arrays (no DB required for sampling logic); cover:
  - Pool of 15 entries: `pool.count ≤ 20` → all 15 included, no shuffle truncation
  - Pool of 30 entries: `pool.count > 20` → `Array(pool.shuffled().prefix(20)).count == 20`
  - All 20 sampled IDs exist within the original pool of 30
  - Pool of exactly 20: all 20 included (boundary check)
  - Pool of 0: no session constructed (empty-state path)
  - Pool of 1: single entry session, no sampling
  - Calling restart twice produces sessions whose card order differs with high probability (run with a pool of ≥ 10 and assert the two arrays are not identical — note this test can theoretically flake with probability (1/10!) ≈ 0; acceptable)
- [X] T0- [X] T030 [US3] Run `swift test --filter LearnSessionRestart` — all must pass; run `swift build` — zero errors; manually verify: complete a session → Restart Session → new session starts with correct pool size

**Checkpoint (US3 done)**: Restart builds a fresh session from the full saved pool, sampling 20 when >20 available. Sampling and pool tests green. `swift test` green.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final integration sweep, edge-case hardening, and full quickstart validation.

- [X] T0- [X] T031 [P] Guard against the "Add to Learn replaces a paused session" edge case: the overwrite in T025 is already implicit (assigning `session = …` replaces any existing value); add an inline comment at the assignment site noting this is intentional per contract C-46 — in `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T0- [X] T032 [P] Guard selection mode against mid-session live captures: confirm that the `ValueObservation` in `VocabularyListView` already fires and adds the new row without a pre-selected checkbox — this is free because `selectedIDs` is a `Set<Int64>` and new entries have IDs not in that set; add a comment confirming this to `ClipboardVocab/UI/VocabularyListView.swift`
- [X] T0- [X] T033 [P] Add `// MARK: - Epic 5 (Inbox Word Management)` section comment above the three new methods in `VocabularyEntryRepository` and add a one-line doc-comment to each of `fetchLearnPool()`, `markMastered(id:)`, `deleteAll(ids:)` in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T0- [X] T034 [P] Add a doc-comment to `FocusSession`'s new `isOnDemand` field explaining that it is set once at init and controls only session header labelling and Restart pool semantics — in `ClipboardVocab/Models/FocusSession.swift`
- [X] T0- [X] T035 Run `swift test` (full suite) — all tests must pass with zero failures; run `swift build` — zero new warnings related to this feature
- [X] T0- [X] T036 Manually validate quickstart.md manual smoke tests 1–7 in sequence to confirm end-to-end integration

**Checkpoint**: All 4 user stories integrated and working end-to-end. Full `swift test` suite green. No new warnings.

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (isMastered column + VocabularyEntry + FocusSession.isOnDemand + updated queue queries)
    └── Phase 2 (fetchLearnPool, markMastered, deleteAll + tests + L10n) ← BLOCKS all story phases
            ├── Phase 3 (US1 — Inbox bulk delete)               ← MVP
            ├── Phase 4 (US4 — Easy = mastered)                  ← can run in parallel with US1
            ├── Phase 5 (US2 — Add to Learn)                     ← depends on US1 for selection state (T014–T016)
            │       and on Phase 1 (FocusSession.isOnDemand)
            └── Phase 6 (US3 — Restart session)                  ← depends on Phase 4 (isMastered exclusion in fetchLearnPool)
                        └── Phase 7 (Polish & final sweep)        ← after all stories
```

- **US1 (bulk delete)** and **US4 (Easy = mastered)** can be developed in parallel after Phase 2.
- **US2 (Add to Learn)** depends on US1 being complete (T014–T016 add the selection state that T024/T025 extend).
- **US3 (Restart)** depends on Phase 4 (mastery exclusion in `fetchLearnPool`) being complete so the pool is correct.
- **Phase 7 (Polish)** runs after all stories are individually verified.

### Parallel Opportunities

- T001 (`VocabularyEntry`) and T002 (`Database` migration) and T005 (`FocusSession`) can be written simultaneously — independent files.
- T003 and T004 (`fetchDueEntries`, `fetchDueCount` filter updates) can be done in parallel — both in the repository file but touching different methods.
- T010 (migration test) and T011 (repository mastery tests) can be written simultaneously — independent files.
- T022 (`MasteryTests`) can be written in parallel with T018 (`InboxSelectionTests`) — independent.
- T029 (`LearnSessionRestartTests`) can be drafted in parallel with T027 (implementation) — tests define the contract.
- T031–T034 (Polish documentation) can all run in parallel — different files or independent comments.

---

## Parallel Example: US1 (Bulk Delete)

```
# After Phase 2 is complete — launch US1 tasks:

Parallel group A (models/state):
  Task T014: Add @State isSelecting + selectedIDs to VocabularyListView
  Task T018: Write InboxSelectionTests (repository layer, independent of UI)

Sequential within Phase 3:
  T015 (toolbar) → T016 (row checkboxes) → T017 (Delete Selected button) → T019 (test run)
```

## Parallel Example: US4 + US1 simultaneously (after Phase 2)

```
Developer A: Phase 3 (US1 — bulk delete): T014 → T015 → T016 → T017 → T018 → T019
Developer B: Phase 4 (US4 — Easy mastery): T020 → T021 → T022 → T023
```

---

## Implementation Strategy

### MVP First (US1 + US4 only — Phases 1–4)

1. Complete Phase 1 (schema v6, model changes, query updates)
2. Complete Phase 2 (repository methods, tests, L10n)
3. Complete Phase 3 (US1 — bulk delete from Inbox)
4. Complete Phase 4 (US4 — Easy = mastered)
5. **STOP and VALIDATE**: `swift test` green; mastered words absent from queue; bulk delete works
6. The two highest-impact changes are live: users can clean up the Inbox in bulk and graduate words permanently

### Full Feature (Phases 1–7)

1. MVP scope above
2. Phase 5: Add to Learn (US2) — on-demand session from Inbox
3. Phase 6: Restart Session (US3) — pool-based restart with 20-card sampling
4. Phase 7: Polish, doc-comments, final `swift test` sweep
5. Validate all quickstart.md manual smoke tests 1–7

---

## Notes

- `[P]` tasks = different files or logically independent additions within the phase — can be assigned to separate agents/developers
- `[USn]` label maps each task to the user story for traceability
- **All view files live in `ClipboardVocab/UI/`** — never `ClipboardVocab/Views/`
- **All new model types live in `ClipboardVocab/Models/`**
- Use `Database(path: ":memory:")` in all test helpers (no tmp file paths)
- `markMastered` is `throws` and callers must `catch` — it is NOT fire-and-forget (unlike `setDifficultyLabel`)
- `deleteAll(ids:)` is `throws` but callers use `try?` (silent failure is acceptable for a batch delete — the user can retry)
- `fetchLearnPool()` returns ALL saved non-mastered entries regardless of `dueDate` — broader than `fetchDueEntries()`
- Random sampling: `pool.count > 20` → `Array(pool.shuffled().prefix(20))`; `pool.count ≤ 20` → use all (no shuffle needed, but no harm if shuffled)
- GRDB column key: `Column("isMastered")` — camelCase matching the SQL column name exactly (AGENTS.md GRDB rule)
- `FocusSession.isOnDemand` is `let` — set once at init, never mutated
- `session.recordRating` is called ONLY after a successful `applyRating` write — same rule as Epic 4
- Mastery write (`markMastered`) for Easy rating: called after `applyRating` succeeds, inside the existing `Task` — do NOT call in ReviewView (mastery is Learn-mode only)
- All L10n strings go through `L10n.string(_:)` — never bare `NSLocalizedString` (AGENTS.md rule)
- The `onNavigateToLearn` callback on `VocabularyListView` must use a weak capture or a simple closure that sets `selectedTab` on `VocabularySidebarView` — no retain cycle risk since both are value-type views
