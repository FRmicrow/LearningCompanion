# Tasks: Learn & Review — Sessions de révision

**Input**: Design documents from `specs/009-learn-review-sessions/`
**Branch**: `dev`
**Prerequisites**: spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/learn-review-sessions.md ✅ · quickstart.md ✅

**Tests**: Required (project convention, matching Epic 3 pattern). Test tasks are included for all new repository methods, in-memory types, utility functions, and the v5 migration.

**Organization**: Tasks map to the five user stories (US1–US5) plus shared foundational work. Each phase is independently buildable and runnable.

> **Path convention**: All new Swift source files live under `ClipboardVocab/UI/` (views) or `ClipboardVocab/Models/` (value types). The SPM target uses `path: "ClipboardVocab"` with recursive discovery — any file placed under `ClipboardVocab/` is automatically included. There is no `Views/` subdirectory; use `UI/` for all view files.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[USn]**: Which user story this task belongs to

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Extend `SRSUpdate` with `lastReviewedDate`, add migration `v5`, add the two new `VocabularyEntry` fields, add the `DifficultyLabel` enum. Every subsequent phase depends on this compiling.

- [X] T001 Add `lastReviewedDate: String` field to `SRSUpdate` struct (value = today's date, `YYYY-MM-DD`, set by `SRSEngine.rate`) in `ClipboardVocab/Services/SRSEngine.swift`
- [X] T002 Update `SRSEngine.rate(_:rating:)` to compute `lastReviewedDate = todayString` (same `Calendar.current` pattern as `dueDate`) and include it in the returned `SRSUpdate` in `ClipboardVocab/Services/SRSEngine.swift`
- [X] T003 Extend `applyRating(id:update:)` in `VocabularyEntryRepository` to write `lastReviewedDate` in the same UPDATE statement (add `, lastReviewedDate = ?` to the existing SET clause, bind `update.lastReviewedDate`) in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T004 Add top-level `DifficultyLabel` enum (`easy`, `medium`, `hard`) with `String` raw values and `Codable` conformance in `ClipboardVocab/Models/DifficultyLabel.swift`
- [X] T005 Add two new optional fields to `VocabularyEntry` (`difficultyLabel: DifficultyLabel?`, `lastReviewedDate: String?`) and extend `CodingKeys` with two new camelCase cases (`difficultyLabel = "difficultyLabel"`, `lastReviewedDate = "lastReviewedDate"`) in `ClipboardVocab/Models/VocabularyEntry.swift`
- [X] T006 Register migration `"v5"` in `Database.migrate()` — add two nullable columns: `ALTER TABLE vocabulary_entries ADD COLUMN difficultyLabel TEXT DEFAULT NULL` and `ALTER TABLE vocabulary_entries ADD COLUMN lastReviewedDate TEXT DEFAULT NULL` in `ClipboardVocab/Persistence/Database.swift`
- [X] T007 Verify `swift build` compiles with all model, migration, and `SRSUpdate` changes before proceeding (zero errors, zero new warnings)

**Checkpoint**: App builds. Existing `swift test` suite still green (T001–T003 are additive changes; all prior `SRSEngine` and repository tests must still pass after adding the new field). Migration `v5` opens without error on a fresh DB.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement and test `setDifficultyLabel`, extend `applyRating` tests to cover `lastReviewedDate`, verify migration `v5`, and implement the `relativeDate` utility. Every user story phase depends on these being correct and tested.

**⚠️ CRITICAL**: No user story work can begin until these tests are green.

- [X] T008 Add `setDifficultyLabel(id: Int64, label: DifficultyLabel) throws` to `VocabularyEntryRepository` — single `dbQueue.write` UPDATE touching only `difficultyLabel` (`UPDATE vocabulary_entries SET difficultyLabel = ? WHERE id = ?`); does not touch SRS columns or `triageStatus` in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T009 [P] Write `@Suite("VocabularyEntryRepositoryEpic4Tests")` in `Tests/Unit/VocabularyEntryRepositoryTests.swift` (extend existing file); use `Database(path: ":memory:")`; cover:
  - `setDifficultyLabel` writes `difficultyLabel` and does not touch any SRS field
  - `setDifficultyLabel` with each `DifficultyLabel` case persists the correct raw string (`"easy"`, `"medium"`, `"hard"`)
  - A second `setDifficultyLabel` call overwrites the previous value correctly (`.hard` then `.easy` → final value is `"easy"`)
  - `applyRating` now also writes `lastReviewedDate` equal to today's date string
  - `applyRating` with `lastReviewedDate` is still atomic (no partial writes on failure)
  - *(Note: the persistence-across-sessions scenario previously planned as T034 is covered here — T034 is reduced to a `swift test` checkpoint only)*
- [X] T010 [P] Write `@Suite("DatabaseMigrationV5Tests")` in `Tests/Unit/DatabaseMigrationV5Tests.swift`; use `Database(path: ":memory:")`; cover:
  - Migration `v5` runs without error on a DB at `v4`
  - Existing rows have `difficultyLabel = NULL` and `lastReviewedDate = NULL` after migration
  - No existing column (including all `v4` SRS columns) is modified or removed
  - Migration is idempotent if applied twice (GRDB migrator handles this)
- [X] T011 [P] Implement two static methods on `RelativeDateFormatter` in `ClipboardVocab/Models/RelativeDateFormatter.swift` (place in `Models/` — no `Utils/` subdirectory needed):
  - `static func lastReviewedLabel(from dateString: String?, today todayString: String) -> String` — nil → `"Never"`, same day → `"Today"`, 1 day ago → `"Yesterday"`, N days ago → `"N days ago"`
  - `static func nextReviewLabel(from dateString: String?, today todayString: String) -> String` — nil → `"Today"`, same day → `"Today"`, 1 day ahead → `"Tomorrow"`, N days ahead → `"In N days"`
  - Both methods use `Calendar.current` for day-difference computation; no UTC conversion
  - Both accept `todayString` as an explicit parameter (not `Date()`) to keep the function pure and deterministic in tests
- [X] T012 [P] Write `@Suite("RelativeDateFormatterTests")` in `Tests/Unit/RelativeDateFormatterTests.swift`; pass both `dateString` and `todayString` as fixed string literals (never `Date()`) for deterministic results; call `lastReviewedLabel` and `nextReviewLabel` by their exact method names; cover:
  - `lastReviewedLabel(from: nil, today: "2025-07-23")` → `"Never"`
  - `nextReviewLabel(from: nil, today: "2025-07-23")` → `"Today"`
  - Same-day input → `"Today"` for both methods
  - `lastReviewedLabel(from: "2025-07-22", today: "2025-07-23")` → `"Yesterday"`
  - `nextReviewLabel(from: "2025-07-24", today: "2025-07-23")` → `"Tomorrow"`
  - `lastReviewedLabel(from: "2025-07-20", today: "2025-07-23")` → `"3 days ago"`
  - `nextReviewLabel(from: "2025-07-30", today: "2025-07-23")` → `"In 7 days"`
- [X] T013 Add L10n keys for all user-visible strings introduced by this feature in `ClipboardVocab/Resources/Localizable.strings`:
  - `"learn_reveal_button"` = `"Reveal"`
  - `"learn_rating_again"` = `"Again"`, `"learn_rating_hard"` = `"Hard"`, `"learn_rating_good"` = `"Good"`, `"learn_rating_easy"` = `"Easy"`
  - `"review_rating_easy"` = `"Easy"`, `"review_rating_medium"` = `"Medium"`, `"review_rating_hard"` = `"Hard"`
  - `"session_header"` = `"Today's Review — %d cards"`
  - `"session_progress"` = `"%d / %d"`
  - `"session_empty_state"` = `"Nothing to review today — come back tomorrow"`
  - `"session_completion_total"` = `"You reviewed %d words"`
  - `"session_write_error"` = `"Couldn't save — will retry"` *(used by T026 write-failure overlay)*
  - `"card_last_review"` = `"Last review"`, `"card_next_review"` = `"Next review"`
  - `"difficulty_easy"` = `"Easy"`, `"difficulty_medium"` = `"Medium"`, `"difficulty_hard"` = `"Hard"`
- [X] T014 Run `swift test --filter VocabularyEntryRepository` and `swift test --filter DatabaseMigration` and `swift test --filter RelativeDateFormatter` — all must pass; run `swift test` (full suite) — all green

**Checkpoint**: `setDifficultyLabel` implemented and tested. `applyRating` extended to write `lastReviewedDate` atomically and tests updated. Migration `v5` verified. Relative date utility tested with fixed inputs. Full `swift test` suite green.

---

## Phase 3: US1 — Completing a Learn Session Card (Priority: P1) 🎯 MVP

**Goal**: A Learn card is displayed with the English word visible and translation hidden. Space/Reveal uncovers the translation and shows rating buttons. Selecting a rating submits the SRS write, advances the card, and updates the progress counter. Rating buttons are unreachable before Reveal.

**Independent Test** (quickstart.md Scenarios 2, 3):
- Open Learn tab with due entries → first card shows English, translation hidden, no rating buttons.
- Press Space → translation visible, four rating buttons appear.
- Press `3` (Good) → card dismissed, next card appears, counter increments.
- Press `1` before Space → no write fires, card remains hidden.

### Implementation — US1

- [X] T015 [US1] Implement `FocusSession` struct in `ClipboardVocab/Models/FocusSession.swift` with:
  *(Note: SPM target uses recursive discovery under `ClipboardVocab/` — new files in `ClipboardVocab/Models/` are picked up automatically.)*
  - `let totalCards: Int`
  - `var cards: [VocabularyEntry]`, `var ratedCount: Int`, `var tally: RatingTally`, `var failedCardIDs: Set<Int64>`
  - `var isComplete: Bool { cards.isEmpty }`, `var current: VocabularyEntry? { cards.first }`
  - `mutating func advance()` — removes `cards[0]`
  - `mutating func recordRating(_ rating: SRSRating)` — increments `tally` field + `ratedCount`
  - `mutating func appendRetry(_ entry: VocabularyEntry)` — appends entry only if `entry.id` not in `failedCardIDs`; then inserts id into `failedCardIDs`
  - Nested `struct RatingTally { var again = 0; var hard = 0; var good = 0; var easy = 0 }`
- [X] T016 [P] [US1] Write `@Suite("FocusSessionTests")` in `Tests/Unit/FocusSessionTests.swift`; use mock `VocabularyEntry` values (in-memory, no DB); cover:
  - `advance()` removes first card; `isComplete` becomes true when `cards` is empty
  - `recordRating(.good)` increments `tally.good` and `ratedCount`; other tally fields unchanged
  - `appendRetry` appends the card to `cards` and inserts id into `failedCardIDs`
  - `appendRetry` with an id already in `failedCardIDs` does NOT append — single-retry enforcement
  - `totalCards` never changes after init regardless of `appendRetry` calls
  - `ratedCount` does NOT increment when `advance()` is called without a preceding `recordRating`
- [X] T017 [US1] Implement `LearnCardView` in `ClipboardVocab/UI/LearnCardView.swift`:
  - `@State var isRevealed: Bool = false`
  - Shows `entry.englishText` as the primary word
  - Shows a Reveal button (and `.keyboardShortcut(" ", modifiers: [])`) that sets `isRevealed = true`
  - Conditionally renders the `frenchTranslation` and the four rating buttons (`Again`, `Hard`, `Good`, `Easy`) only when `isRevealed == true` — this single condition covers both visual gating and keyboard shortcut blocking
  - Each rating button has a `.keyboardShortcut` keyed to `"1"`–`"4"` respectively
  - Rating button action: calls `onRate(SRSRating)` callback (passed in via closure parameter); resets `isRevealed = false`
  - Also renders `DifficultySelector` (F-404, implemented in T032) and `ReviewMetadataFooter` (F-405, implemented in T029) unconditionally — pass `entry` and `repository` through; these subviews are stubs/placeholders until their respective tasks are implemented
- [X] T018 [US1] Implement `LearnView` in `ClipboardVocab/UI/LearnView.swift`:
  - Holds `@Binding var session: FocusSession?` (passed from `VocabularySidebarView` container — wired in T025)
  - On `.onAppear`: call `repository.fetchDueEntries()` once (synchronous, one-shot) to load the initial due count for the idle/empty state check; reactive observation is wired later in T036
  - If `session == nil` and due entries exist, shows "Start Today's Review" button; if `session != nil`, shows the current card
  - "Start Today's Review" button: calls `repository.fetchDueEntries()`, initialises `FocusSession(totalCards: entries.count, cards: entries, ratedCount: 0, tally: .init(), failedCardIDs: [])`, assigns to `session`
  - Shows empty state (`L10n.string("session_empty_state")`) when no due entries and `session == nil`
  - Displays session header `"Today's Review — \(session.totalCards) cards"` and progress counter `"\(session.ratedCount) / \(session.totalCards)"` during an active session
  - The `onRate` callback from `LearnCardView` handles **happy path only**: `Task { do { let update = SRSEngine.rate(card, rating: rating); try repository.applyRating(id: card.id!, update: update); await MainActor.run { session?.recordRating(rating); session?.advance(); if session?.isComplete == true { showCompletion = true } } } catch { /* error path wired in T026 */ } }`
  - When `session?.isComplete == true`, presents `SessionCompletionView` (implemented in T024)
- [X] T019 [US1] Run `swift test --filter FocusSession` — all tests must pass; run `swift build` — zero errors

**Checkpoint (US1 done)**: Learn card renders, Reveal/rate cycle works, session counter advances, rating buttons blocked before Reveal. `FocusSession` fully unit-tested. `swift test` green.

---

## Phase 4: US2 — Completing a Review Session Card (Priority: P1)

**Goal**: A Review card shows the French translation first. Reveal uncovers the English word. Three rating buttons (Easy / Medium / Hard) appear. Medium maps to the `.good` SRS rating. The same `FocusSession` and `applyRating` machinery drives Review mode identically to Learn mode.

**Independent Test** (quickstart.md Scenario 4):
- Open Review tab → card shows French, English hidden, no rating buttons.
- Press Space → English appears, three buttons appear.
- Tap Medium → SRS write fires with `.good` rating; card advances.

### Implementation — US2

- [X] T020 [US2] Implement `ReviewCardView` in `ClipboardVocab/UI/ReviewCardView.swift`:
  - Mirrors `LearnCardView` structure with `@State var isRevealed: Bool = false`
  - Shows `entry.frenchTranslation` as the primary text (use `entry.frenchTranslation ?? ""`)
  - Reveal button and `.keyboardShortcut(" ", modifiers: [])` uncover `entry.englishText`
  - Conditionally renders three rating buttons (`Easy`, `Medium`, `Hard`) only when `isRevealed == true`
  - Rating button keyboard shortcuts: `"1"` = Easy, `"2"` = Medium, `"3"` = Hard
  - Extract the mapping as a pure nested enum or free function in this file: `ReviewRating` with cases `easy`, `medium`, `hard` and a `var toSRSRating: SRSRating` computed property (`easy → .easy`, `medium → .good`, `hard → .hard`) — this makes T022 unit-testable without a UI harness
  - Rating button action: map `ReviewRating` to `SRSRating` via `toSRSRating`, then call `onRate(SRSRating)` with the mapped value; reset `isRevealed = false`
  - Also renders `DifficultySelector` and `ReviewMetadataFooter` unconditionally (same stub pattern as T017)
- [X] T021 [P] [US2] Implement `ReviewView` in `ClipboardVocab/UI/ReviewView.swift`:
  - Mirrors `LearnView` structure; holds `@Binding var session: FocusSession?`
  - Shares the same `FocusSession` binding as `LearnView` (same `@State` on the container, passed down as `$session`) — this enforces the single shared queue (C-43 clarification)
  - The `onRate` callback uses the identical error-handling path as in `LearnView` (T018)
  - Shows the same session header, progress counter, empty state, and completion screen
- [X] T022 [US2] Write `@Suite("ReviewRatingMappingTests")` in `Tests/Unit/ReviewRatingMappingTests.swift`; test the `ReviewRating.toSRSRating` computed property defined in T020 (pure function, no UI harness required):
  - `ReviewRating.medium.toSRSRating == .good`
  - `ReviewRating.easy.toSRSRating == .easy`
  - `ReviewRating.hard.toSRSRating == .hard`
- [X] T023 [US2] Run `swift build` — zero errors; manually verify (or via UI snapshot if available): Review tab card shows French first, Reveal uncovers English, Medium submits `.good` to the engine

**Checkpoint (US2 done)**: Review mode works symmetrically with Learn mode. Rating mapping confirmed (Medium → Good). Shared queue enforced via single `@State` binding. `swift test` green.

---

## Phase 5: US3 — Running a Focus Session (Priority: P1)

**Goal**: "Start Today's Review" captures the queue snapshot, drives cards in sequence with a live counter, handles write failures by re-queueing once, and shows a completion screen with total + rating tally when the queue is drained.

**Independent Test** (quickstart.md Scenarios 5, 7, 8, 9):
- 3 due cards → start session → header "Today's Review — 3 cards", counter "0 / 3".
- Rate each → counter advances to "3 / 3" → completion screen shows totals + tally.
- Switch tab mid-session → return → session resumes at correct card.
- Write failure on card 2 → inline error → card appended to end → session completes with retry.

### Implementation — US3

- [X] T024 [US3] Implement `SessionCompletionView` in `ClipboardVocab/UI/SessionCompletionView.swift`:
  - Accepts `ratedCount: Int` and `tally: FocusSession.RatingTally`
  - Displays `L10n.string("session_completion_total")` formatted with `ratedCount`
  - Displays a compact rating breakdown row: `"Again: \(tally.again)  Hard: \(tally.hard)  Good: \(tally.good)  Easy: \(tally.easy)"`
  - Has a "Done" / dismiss button that clears the `session` binding (sets to `nil`) and resets the `LearnView` / `ReviewView` to idle state
- [X] T025 [P] [US3] Wire `FocusSession` state into the existing tab container in `ClipboardVocab/UI/VocabularySidebarView.swift`:
  - Add `@State private var focusSession: FocusSession?` to `VocabularySidebarView`
  - In `contentForTab(.learn)`, replace the current `Text(L10n.string("learn_placeholder_label"))` stub with `LearnView(repository: repository, session: $focusSession)`
  - In `contentForTab(.review)`, replace the current `Text(L10n.string("review_placeholder_label"))` stub with `ReviewView(repository: repository, session: $focusSession)`
  - The `@State` lives on `VocabularySidebarView` (not on `LearnView`/`ReviewView`), so it is never reset when switching tabs — session naturally persists across `.inbox` / `.stats` switches
- [X] T026 [US3] Complete the write-failure error path in `LearnView` (`ClipboardVocab/UI/LearnView.swift`) and `ReviewView` (`ClipboardVocab/UI/ReviewView.swift`) — this is the `catch` block left as `/* error path wired in T026 */` in T018:
  - Add `@State private var showInlineError: Bool = false` to each view
  - In the `catch` block: `await MainActor.run { showInlineError = true; session?.appendRetry(card); session?.advance() }` — do NOT call `session?.recordRating` on failure
  - Render a transient error indicator as an `.overlay` on the card: `Text(L10n.string("session_write_error"))` — add `"session_write_error"` = `"Couldn't save — will retry"` to `Localizable.strings` (T013)
  - Auto-dismiss after 2 seconds: `Task { try? await Task.sleep(for: .seconds(2)); await MainActor.run { showInlineError = false } }` (use `Duration`-based sleep, not raw nanoseconds)
- [X] T027 [US3] Add `@Suite("FocusSessionRetryTests")` in `Tests/Unit/FocusSessionTests.swift`; cover:
  - Full session of 3 cards: `recordRating` + `advance` × 3 → `isComplete == true`, `ratedCount == 3`, tally sums to 3
  - Write failure on card 1: `appendRetry` + `advance` (no `recordRating`) → card appears at end; then `recordRating` + `advance` on retry → `isComplete == true`, `ratedCount == 2` (only 2 successful writes for 3 original cards, 1 retry)
  - Double failure on same card: first `appendRetry` succeeds (card added), second `appendRetry` is a no-op (id already in `failedCardIDs`)
  - `totalCards` = 3 throughout all of the above (never changes)
  - **Session pause/resume preservation test**: init `FocusSession` with 5 entries; call `advance()` twice (simulating 2 successful ratings); assert `session.current` is the third entry, `session.ratedCount == 0` (advance-only, no ratings recorded), `session.cards.count == 3`; this confirms that navigating away (which triggers no mutation) leaves session state intact
- [X] T028 [US3] Run `swift test --filter FocusSession` — all tests including T027 must pass; run `swift build` — zero errors

**Checkpoint (US3 done)**: Focus Session complete — snapshot, progress, completion screen, tab-switch pause/resume, write-failure retry. `swift test` green.

---

## Phase 6: US4 — Review Metadata on a Card (Priority: P2)

**Goal**: Every card renders a metadata footer showing "Last review: [relative]" and "Next review: [relative]" computed from `lastReviewedDate` and `dueDate`. Values survive a session and display correctly for new entries that have never been reviewed.

**Independent Test** (quickstart.md Scenario 6):
- Card with `lastReviewedDate = yesterday`, `dueDate = tomorrow` → footer shows "Yesterday" / "Tomorrow".
- Card with `lastReviewedDate = nil`, `dueDate = today` → footer shows "Never" / "Today".

### Implementation — US4

- [X] T029 [US4] Implement `ReviewMetadataFooter` view in `ClipboardVocab/UI/ReviewMetadataFooter.swift`:
  - Accepts `entry: VocabularyEntry`
  - Computes `lastReviewLabel = RelativeDateFormatter.lastReviewedLabel(from: entry.lastReviewedDate, today: todayString())` where `todayString()` is a private helper using `Calendar.current` + `"yyyy-MM-dd"` format (same pattern as `SRSEngine`)
  - Computes `nextReviewLabel = RelativeDateFormatter.nextReviewLabel(from: entry.dueDate, today: todayString())`
  - Renders two rows: `L10n.string("card_last_review") + ": " + lastReviewLabel` and `L10n.string("card_next_review") + ": " + nextReviewLabel`
  - Uses `.foregroundStyle(.secondary)` and `.font(.caption)` (muted, below card content)
  - After implementing, confirm it compiles inside the stubs already added to `LearnCardView` (T017) and `ReviewCardView` (T020)
- [X] T031 [US4] Run `swift test --filter RelativeDateFormatter` (already written in T012) to confirm the formatter covers all metadata display cases; add any missing edge cases found during view wiring (e.g., same-day `lastReviewedDate` displays "Today")

**Checkpoint (US4 done)**: Metadata footer rendered on all cards with correct relative date strings. All formatter tests pass. `swift test` green.

---

## Phase 7: US5 — Difficulty Indicator on a Card (Priority: P2)

**Goal**: An Easy / Medium / Hard radio selector appears on every card. Tapping a value immediately fires a standalone `setDifficultyLabel` write (fire-and-forget). The pre-selected value persists across sessions.

**Independent Test** (quickstart.md Scenario 5):
- Card displays — selector shows no selection (new entry, `difficultyLabel == nil`).
- Tap Hard → `setDifficultyLabel` write fires; close and reopen session → same card pre-selects Hard.

### Implementation — US5

- [X] T032 [US5] Implement `DifficultySelector` view in `ClipboardVocab/UI/DifficultySelector.swift`:
  - Accepts `entry: VocabularyEntry` and `repository: VocabularyEntryRepository`
  - Uses `@State private var selected: DifficultyLabel? = entry.difficultyLabel` initialised from the entry
  - Renders three radio/picker-style buttons: Easy, Medium, Hard (using `L10n.string("difficulty_easy")` etc.)
  - On tap: sets `selected = tapped`, then fires `Task { try? repository.setDifficultyLabel(id: entry.id!, label: tapped) }` immediately (fire-and-forget, no error handling)
  - When `selected == nil`, no button is pre-highlighted
  - When `selected != nil`, the matching button is highlighted/selected
- [X] T033 [US5] After implementing `DifficultySelector`, confirm it compiles inside the stubs already added to `LearnCardView` (T017) and `ReviewCardView` (T020) — run `swift build` to verify
- [X] T034 [US5] Run `swift test --filter VocabularyEntryRepository` — the overwrite scenario already covered in T009 must pass; run `swift build` — zero errors

**Checkpoint (US5 done)**: Difficulty selector renders, writes immediately, persists across sessions, overwrites correctly. `swift test` green.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final integration sweep, persistence check, observation wiring, and full quickstart validation. Runs after all user stories are individually confirmed working.

- [X] T036 Replace the one-shot `fetchDueEntries()` call in `LearnView` and `ReviewView` (added in T018) with a reactive `ValueObservation` following the established pattern from `specs/008-srs-engine/contracts/srs-engine.md`:
  - Add `@State private var dueEntries: [VocabularyEntry] = []` and `@State private var observationTask: Task<Void, Never>?` to `ClipboardVocab/UI/LearnView.swift` and `ClipboardVocab/UI/ReviewView.swift`
  - Start observation in `.onAppear` via `Task { @MainActor in for try await entries in observation.values(in: repository.dbQueue) { self.dueEntries = entries } }`, cancel in `.onDisappear`
  - The idle-state "Start Today's Review" button and empty state now react to live queue changes without re-fetch
- [X] T036b Update `VocabularySidebarView.startProgressObservation()` in `ClipboardVocab/UI/VocabularySidebarView.swift` to use the Epic 3 daily queue count query instead of the current `firstCapturedAt` filter:
  - Replace the existing `ValueObservation` body with: `try VocabularyEntry.filter(Column("triageStatus") == "saved").filter(Column("dueDate") <= todayString).fetchCount(db)` where `todayString` is computed via `Calendar.current` + `"yyyy-MM-dd"` format
  - This ensures `DailyProgressBar` reflects cards due today (matching the Learn/Review queue) rather than cards captured today
- [X] T037 [P] Add doc-comments to `FocusSession` explaining the single-retry invariant (`failedCardIDs`) and why `totalCards` is immutable; add a comment to `appendRetry` noting the no-op behaviour for already-failed IDs in `ClipboardVocab/Models/FocusSession.swift`
- [X] T038 [P] Add a `// MARK: - Epic 4 (Learn & Review)` section header to `VocabularyEntryRepository` above `setDifficultyLabel`; add a doc-comment explaining the fire-and-forget caller convention in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [X] T039 Write `@Suite("LearnReviewPersistenceTests")` in `Tests/Unit/VocabularyEntryRepositoryTests.swift`: create DB (use a temp file path, not `:memory:`, to test restart survival), apply a rating (with `lastReviewedDate`), apply a difficulty label, close `DatabaseQueue`, re-open from same path, fetch entry — assert `lastReviewedDate`, `difficultyLabel`, and all SRS fields are unchanged from pre-close values
- [X] T040 Run `swift test` (full suite) — all tests must pass with zero failures; run `swift build` — zero warnings related to this feature; manually time the card transition after rating (tap a rating, measure time to next card appearance) and confirm it feels instantaneous (≤ 200 ms target from SC-2)
- [X] T041 Manually validate quickstart.md Scenarios 1–11 in sequence to confirm end-to-end integration (requires Epic 1 sidebar tab navigation and Epic 3 SRS engine to be in place for full UI scenarios)

**Checkpoint**: Complete Learn & Review sessions working end-to-end. Persistence confirmed. `ValueObservation` wired. Full `swift test` suite green.

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Schema v5 + DifficultyLabel + SRSUpdate extension)
    └── Phase 2 (setDifficultyLabel + applyRating extension + RelativeDateFormatter)  ← BLOCKS all story phases
            ├── Phase 3 (US1 — Learn card + FocusSession)     ← MVP
            │       └── Phase 4 (US2 — Review card)           ← mirrors US1, depends on FocusSession
            │               └── Phase 5 (US3 — Focus Session wiring + completion screen)
            ├── Phase 6 (US4 — Review metadata footer)         ← depends on RelativeDateFormatter only; parallel with US1–US3
            └── Phase 7 (US5 — Difficulty selector)            ← depends on setDifficultyLabel only; parallel with US1–US3
                            └── Phase 8 (Polish & final sweep) ← after all stories; includes T036, T036b, T039, T040
```

- **US4 (metadata)** and **US5 (difficulty)** depend only on Phase 2 and can be developed in parallel with US1–US3.
- **US2 (Review mode)** depends on US1 being complete (`FocusSession` and `LearnCardView` pattern must exist first to mirror).
- **US3 (Focus Session wiring)** depends on US1 + US2 being complete (both views must exist for container integration in T025).
- **Phase 8 (Polish)** must run last — it requires all views and write paths to exist. T036b (progress bar fix) can be done at any point after Phase 1.

### Parallel Opportunities

- T001–T004 (type definitions: `lastReviewedDate` on `SRSUpdate`, `SRSEngine` update, `DifficultyLabel` enum) can be written in parallel — logically independent.
- T009 (repository tests) and T010 (migration tests) and T011 (RelativeDateFormatter impl, now in `Models/`) and T012 (formatter tests) can all run in parallel in Phase 2 — different files, no ordering constraint.
- T015 (`FocusSession`) and T016 (`FocusSessionTests`) can be drafted simultaneously — tests define the contract before implementation.
- T020 (`ReviewCardView`) and T021 (`ReviewView`) can run in parallel with T029 (`ReviewMetadataFooter`) — different files.
- T036–T038 (Phase 8 documentation + observation wiring) can all run in parallel.

---

## Implementation Strategy

### MVP (US1 only — Phases 1–3)

1. Complete Phase 1 (migration `v5`, `DifficultyLabel`, `SRSUpdate` + `SRSEngine` extension)
2. Complete Phase 2 (repository methods, formatter, tests)
3. Complete Phase 3 (US1 — `FocusSession` + `LearnCardView` + `LearnView`)
4. **STOP and VALIDATE**: `swift test` green; quickstart.md Scenarios 2, 3 pass; rating blocks before Reveal confirmed
5. The Learn session is usable end-to-end: a user can open the Learn tab, start a session, reveal cards, rate them, and see the completion screen

### Full Feature (Phases 1–8)

1. MVP scope above
2. Phase 4: Review mode (`ReviewCardView` + `ReviewView`) — US2
3. Phase 5: Focus Session wiring (`SessionCompletionView`, container binding, write-failure handling) — US3
4. Phase 6: Metadata footer (`ReviewMetadataFooter`) — US4
5. Phase 7: Difficulty selector (`DifficultySelector`) — US5
6. Phase 8: Polish, observation wiring, persistence test, final sweep
7. Final `swift test` (full suite) + quickstart.md all 11 scenarios

---

## Notes

- `[P]` tasks = different files or logically independent additions within the phase — can be assigned to separate agents/developers
- `[USn]` label maps each task to the user story for traceability
- **All view files live in `ClipboardVocab/UI/`** — never `ClipboardVocab/Views/` (that directory does not exist)
- **All new model/utility types live in `ClipboardVocab/Models/`** — `RelativeDateFormatter` is in `Models/`, not a separate `Utils/` directory
- The tab container is **`VocabularySidebarView`** — `@State var focusSession` is declared there; `VocabularyListView` is the Inbox-only content view
- Use `Database(path: ":memory:")` in all test helpers except T039 which explicitly tests persistence across restart
- `applyRating` is `throws` — callers in `LearnView` / `ReviewView` MUST `catch` and apply the re-queue behaviour; never call with `try?` at the UI layer
- `setDifficultyLabel` IS called with `try?` at the UI layer — silent failure is intentional (Research Decision 4)
- `SRSEngine.rate` is NOT `throws` — pure function; never add `try` at call sites
- GRDB column keys: `Column("difficultyLabel")` and `Column("lastReviewedDate")` — camelCase matching SQL column names exactly (AGENTS.md GRDB rule)
- `ReviewView` and `LearnView` MUST share the same `FocusSession` binding from `VocabularySidebarView` — two separate `@State` properties would reset the session on tab switch (Research Decision 3)
- `session.recordRating` is called ONLY after a successful `applyRating` write — not on failure (contract C-44)
- `session.totalCards` is set once at init and never mutated — the header "Today's Review — N cards" always shows the original snapshot count
- Review mode rating mapping (Medium → `.good`) is implemented as `ReviewRating.toSRSRating` (pure computed property in T020) — the SRS engine never receives a raw `"medium"` value (contract C-57, C-58)
- All L10n strings go through `L10n.string(_:)` — never bare `NSLocalizedString` (AGENTS.md L10n rule)
