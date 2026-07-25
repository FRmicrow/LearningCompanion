# Tasks: Inbox — Capture & Triage

**Input**: Design documents from `specs/007-inbox-capture-triage/`  
**Branch**: `007-inbox-capture-triage`  
**Prerequisites**: plan.md ✅ · spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/inbox-view.md ✅ · quickstart.md ✅

**Tests**: Required per Constitution Principle III (Gate 3). Test tasks are included for all new repository methods and the v3 migration.

**Organization**: Tasks map to the four user stories (US1–US4) plus shared foundational work. Each phase is independently buildable and runnable.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[USn]**: Which user story this task belongs to

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the `triageStatus` column to the data model and migration. These tasks are prerequisites for every user story — no Inbox feature can work without the schema change.

- [ ] T001 Add `TriageStatus` enum to `VocabularyEntry` (`unreviewed`, `saved`, `ignored`, `known`) with `String` raw values in `ClipboardVocab/Models/VocabularyEntry.swift`
- [ ] T002 Add `triageStatus: TriageStatus` stored field to `VocabularyEntry` struct; add `triageStatus = "triageStatus"` to `CodingKeys` in `ClipboardVocab/Models/VocabularyEntry.swift`
- [ ] T003 Register migration `"v3"` in `Database.migrate()`: `ALTER TABLE vocabulary_entries ADD COLUMN triageStatus TEXT NOT NULL DEFAULT 'unreviewed'` + `CREATE INDEX idx_vocabulary_triage_status ON vocabulary_entries (triageStatus)` in `ClipboardVocab/Persistence/Database.swift`
- [ ] T004 Verify `swift build` compiles successfully with the model change before proceeding

**Checkpoint**: App builds. Existing tests still pass. `swift test` green. New DB opens with `triageStatus` column; existing rows get the `'unreviewed'` default.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: New repository methods and their tests. Required by all subsequent user story phases.

**⚠️ CRITICAL**: No user story UI work can begin until repository methods and their tests are green.

- [ ] T005 Add `fetchInbox() throws -> [VocabularyEntry]` to `VocabularyEntryRepository` — filters `triageStatus == 'unreviewed'`, orders by `firstCapturedAt` DESC in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [ ] T006 [P] Add `fetchInboxCount() throws -> Int` to `VocabularyEntryRepository` — COUNT query on `triageStatus == 'unreviewed'` in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [ ] T007 [P] Add `markSaved(id: Int64) throws` to `VocabularyEntryRepository` — sets `triageStatus = 'saved'` in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [ ] T008 [P] Add `markIgnored(id: Int64) throws` to `VocabularyEntryRepository` — sets `triageStatus = 'ignored'` in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [ ] T009 [P] Add `markKnown(id: Int64) throws` to `VocabularyEntryRepository` — sets `triageStatus = 'known'` in `ClipboardVocab/Persistence/VocabularyEntryRepository.swift`
- [ ] T010 Write `@Suite("VocabularyEntryRepositoryTriageTests")` in `Tests/Unit/VocabularyEntryRepositoryTriageTests.swift` using in-memory DB (`Database(path: ":memory:")`); cover: `fetchInbox()` returns only `unreviewed` entries, `fetchInboxCount()` returns correct count, `markSaved` / `markIgnored` / `markKnown` each change `triageStatus` and remove the entry from `fetchInbox()`, `upsert` new entry lands in `fetchInbox()`, re-capturing an `ignored` entry keeps it `ignored`
- [ ] T011 Write `@Suite("DatabaseMigrationV3Tests")` in `Tests/Unit/DatabaseMigrationV3Tests.swift`: verify v3 migration runs without error on a fresh in-memory DB; verify existing rows inserted before v3 get `triageStatus = 'unreviewed'` after migration
- [ ] T012 Run `swift test --filter VocabularyEntryRepository` and `swift test --filter DatabaseMigration` — all new tests must pass

**Checkpoint**: All repository methods implemented and tested. Migration v3 verified. `swift test` fully green.

---

## Phase 3: US1 — Reviewing and Saving a New Word (Priority: P1) 🎯 MVP

**Goal**: The Inbox tab shows captured words with hidden translations. The user can reveal a translation and save a word to their vocabulary list. This is the core triage flow.

**Independent Test** (quickstart.md Scenarios 1, 2, 3, 10, 12, 13):
- Copy an English word → it appears in the Inbox within ~1 s.
- Tap Reveal → translation shown (or pending indicator).
- Tap Save → card disappears; `triageStatus` becomes `saved`.
- Copy the same word again → it does not create a duplicate card.
- Stop LibreTranslate → Reveal shows "Translation pending…", Save still works.

### Implementation — US1

- [ ] T013 Create `InboxView.swift` stub (`struct InboxView: View { var body: some View { EmptyView() } }`) in `ClipboardVocab/UI/InboxView.swift`
- [ ] T014 [P] Create `InboxEntryCard.swift` stub (`struct InboxEntryCard: View { ... }`) in `ClipboardVocab/UI/InboxEntryCard.swift`
- [ ] T015 [US1] Implement `InboxView` body: `ValueObservation` on `triageStatus == 'unreviewed'` started in `.onAppear`, cancelled in `.onDisappear`, result stored in `@State private var entries: [VocabularyEntry]`; render `List { ForEach(entries) { InboxEntryCard(...) } }` in `ClipboardVocab/UI/InboxView.swift`
- [ ] T016 [US1] Implement `InboxEntryCard` display: show `entry.englishText` in headline font; show `@State private var isRevealed = false`; when `isRevealed == false` show "Tap to reveal" button; when `isRevealed == true` and `translationStatus == .translated` show `"→ \(frenchTranslation!)"`; when `isRevealed == true` and `.pending` show "Translation pending…"; when `isRevealed == true` and translation nil show "Translation unavailable" in `ClipboardVocab/UI/InboxEntryCard.swift`
- [ ] T017 [US1] Add **Save** and **Reveal** action buttons to `InboxEntryCard`; Save calls `onSave` closure; Reveal sets `isRevealed = true` in `ClipboardVocab/UI/InboxEntryCard.swift`
- [ ] T018 [US1] Wire `InboxView` triage closures: `onSave: { Task { try? repository.markSaved(id: entry.id!) } }` (ValueObservation auto-refreshes the list) in `ClipboardVocab/UI/InboxView.swift`
- [ ] T019 [US1] Replace `VocabularyListView(...)` with `InboxView(repository: repository, translationService: translationService)` in the `.inbox` case of `VocabularySidebarView.contentForTab(_:)` in `ClipboardVocab/UI/VocabularySidebarView.swift`
- [ ] T020 [US1] Apply `.retryPendingOnAppear(for: translationService)` modifier to `InboxView` (same pattern as `VocabularyListView`) in `ClipboardVocab/UI/InboxView.swift`
- [ ] T021 [US1] Run `swift build` and manually validate quickstart.md Scenarios 1, 2, 3, 10, 12, 13

**Checkpoint (US1 done)**: Words appear in the Inbox. Translation reveal works. Saving a word removes it from the Inbox. `swift test` green.

---

## Phase 4: US2 — Ignoring an Irrelevant Word (Priority: P2)

**Goal**: The user can tap **Ignore** on a card to discard it from the Inbox without saving it. When the last entry is triaged, an empty state is shown.

**Independent Test** (quickstart.md Scenarios 4, 5):
- Tap Ignore on a card → card disappears; word does NOT appear in vocabulary list.
- Ignore the last card → Inbox empty state is displayed with no residual entries.

### Implementation — US2

- [ ] T022 [US2] Add **Ignore** button to `InboxEntryCard` (secondary / destructive style); calls `onIgnore` closure in `ClipboardVocab/UI/InboxEntryCard.swift`
- [ ] T023 [US2] Wire `onIgnore` in `InboxView`: `Task { try? repository.markIgnored(id: entry.id!) }` in `ClipboardVocab/UI/InboxView.swift`
- [ ] T024 [US2] Create `InboxEmptyStateView` (a new empty-state view specific to the Inbox, e.g. SF Symbol `tray` + "No new words" message) in `ClipboardVocab/UI/InboxView.swift` (can be a private inner struct or extension in the same file)
- [ ] T025 [US2] Render `InboxEmptyStateView` when `entries.isEmpty` in `InboxView.body` in `ClipboardVocab/UI/InboxView.swift`
- [ ] T026 [US2] Run `swift build` and manually validate quickstart.md Scenarios 4, 5

**Checkpoint (US2 done)**: Ignore action works. Empty state appears correctly. Saved words and ignored words both disappear from the Inbox. `swift test` green.

---

## Phase 5: US3 — Swipe Gestures (Priority: P3)

**Goal**: Swipe-left on a card reveals a destructive Delete action (marks `ignored`). Swipe-right reveals a green Known action (marks `known`). Both complete within 300 ms.

**Independent Test** (quickstart.md Scenarios 6, 7):
- Swipe left → red Delete button visible; tap → card disappears (`ignored`).
- Swipe right → green Known button visible; tap → card disappears (`known`).
- Other cards unaffected after each swipe.

### Implementation — US3

- [ ] T027 [US3] Add `.swipeActions(edge: .trailing, allowsFullSwipe: true)` with a destructive **Delete** `Button` (red, SF Symbol `trash`) calling `onIgnore` on each `InboxEntryCard` row inside the `List` in `ClipboardVocab/UI/InboxView.swift`
- [ ] T028 [US3] Add `.swipeActions(edge: .leading, allowsFullSwipe: true)` with a **Known** `Button` (tint `.green`, SF Symbol `checkmark`) calling `onKnown` on each `InboxEntryCard` row inside the `List` in `ClipboardVocab/UI/InboxView.swift`
- [ ] T029 [US3] Wire `onKnown` in `InboxView`: `Task { try? repository.markKnown(id: entry.id!) }` in `ClipboardVocab/UI/InboxView.swift`
- [ ] T030 [US3] Run `swift build` and manually validate quickstart.md Scenarios 6, 7

**Checkpoint (US3 done)**: Both swipe directions work. Delete marks `ignored`, Known marks `known`. `swift test` green.

---

## Phase 6: US4 — Menu-Bar Badge (Priority: P4)

**Goal**: When words are pending in the Inbox, the menu-bar icon shows a badge with the count. Badge clears when the Inbox is empty. Updates within 1 s of a capture or triage action.

**Independent Test** (quickstart.md Scenarios 8, 9):
- Close sidebar; copy 3 words → badge shows "3" within ~1 s.
- Triage all words → badge disappears.

### Implementation — US4

- [ ] T031 [US4] Add `private var badgeTask: Task<Void, Never>?` property to `StatusItemController` in `ClipboardVocab/UI/StatusItemController.swift`
- [ ] T032 [US4] Implement `updateBadge(count: Int)` on `StatusItemController`: when `count == 0` restore base icon; when `count > 0` draw a filled red circle (10 pt) at bottom-right of base icon with white count text capped at "9+" using `NSImage` drawing context in `ClipboardVocab/UI/StatusItemController.swift`
- [ ] T033 [US4] Implement `startBadgeObservation(repository: VocabularyEntryRepository)` on `StatusItemController`: create `ValueObservation` on `fetchInboxCount()`, store `Task { @MainActor in ... }` in `badgeTask`, call `updateBadge(count:)` on each update in `ClipboardVocab/UI/StatusItemController.swift`
- [ ] T034 [US4] Call `startBadgeObservation(repository: repository)` at the end of `StatusItemController.init(repository:translationService:)` in `ClipboardVocab/UI/StatusItemController.swift`
- [ ] T035 [US4] Write `@Suite("StatusItemBadgeTests")` in `Tests/Unit/StatusItemBadgeTests.swift`: inject a test repository backed by `Database(path: ":memory:")`, insert entries, verify `fetchInboxCount()` changes drive the correct badge count value (test the count logic, not the image drawing)
- [ ] T036 [US4] Run `swift test --filter StatusItemBadge` — must pass; run `swift build` and manually validate quickstart.md Scenarios 8, 9

**Checkpoint (US4 done)**: Badge appears and clears correctly. All four user stories are fully functional. `swift test` fully green.

---

## Phase 7: Keyboard Shortcuts & Polish

**Purpose**: Keyboard-only triage flow (SC-001). Adapts the existing `InboxKeyboardShortcutsModifier` pattern to `InboxView`. Runs after all stories are individually confirmed working.

- [ ] T037 Add `InboxKeyboardShortcutsModifier` (private `ViewModifier`) to `InboxView.swift`: `Space` → reveal top entry (`isRevealed` on first card — requires passing `@Binding var isRevealed` to the first card or using a dedicated `@State var topRevealed`); `⌘H` → toggle top entry reveal; `Enter` → save top entry in `ClipboardVocab/UI/InboxView.swift`
- [ ] T038 Apply `InboxKeyboardShortcutsModifier` to `InboxView.body` in `ClipboardVocab/UI/InboxView.swift`
- [ ] T039 Add L10n keys for new strings: `"inbox_reveal_button"`, `"inbox_save_button"`, `"inbox_ignore_button"`, `"inbox_known_swipe_label"`, `"inbox_delete_swipe_label"`, `"inbox_empty_state_message"`, `"inbox_translation_pending_label"`, `"inbox_translation_unavailable_label"` in `ClipboardVocab/Resources/Localizable.strings`
- [ ] T040 Replace all inline French strings added in T013–T038 with `L10n.string(...)` calls in `ClipboardVocab/UI/InboxView.swift` and `ClipboardVocab/UI/InboxEntryCard.swift`
- [ ] T041 Run `swift test` (full suite) — all tests must pass; manually validate quickstart.md Scenario 11 (keyboard-only triage)

**Checkpoint**: Complete feature working end-to-end, keyboard shortcuts confirmed, all strings localised, `swift test` fully green.

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Schema)
    └── Phase 2 (Repository + Tests)  ← BLOCKS all UI phases
            ├── Phase 3 (US1 — Save)           ← MVP
            │       └── Phase 4 (US2 — Ignore) ← builds on Phase 3 empty-state
            │               └── Phase 5 (US3 — Swipe)
            └── Phase 6 (US4 — Badge)          ← independent of Phase 3–5
                        └── Phase 7 (Keyboard & Polish) ← after all stories
```

- **US4 (Badge)** depends only on Phase 2 and can be developed in parallel with US1–US3.
- **US1 (Save)** must precede US2 (Ignore) because US2 relies on the `InboxEmptyStateView` path that US1's list renders.
- **US3 (Swipe)** requires US2 (Ignore) to be complete so `onIgnore` is already wired.

### Parallel Opportunities

- T005–T009 (repository method stubs) can all be written in parallel — they are all additions to the same file with no internal dependencies.
- T013 (`InboxView` stub) and T014 (`InboxEntryCard` stub) can be created in parallel — different files.
- T031–T034 (badge) can be worked in parallel with T013–T021 (US1 view) after Phase 2 is complete.

---

## Implementation Strategy

### MVP (US1 only — Phases 1–3)

1. Complete Phase 1 (Schema + model change)
2. Complete Phase 2 (Repository + tests)
3. Complete Phase 3 (US1 — Save flow)
4. **STOP and VALIDATE**: quickstart.md Scenarios 1, 2, 3, 10, 12, 13
5. The app is usable: words appear in the Inbox and can be saved

### Full Feature (Phases 1–7)

1. MVP scope above
2. Phase 4: Ignore + empty state
3. Phase 5: Swipe gestures
4. Phase 6: Menu-bar badge
5. Phase 7: Keyboard shortcuts + L10n polish
6. Final `swift test` (full suite) + quickstart.md all 13 scenarios

---

## Notes

- `[P]` tasks = different files, no internal dependencies within the phase
- `[USn]` label maps each task to the user story for traceability
- Use `Database(path: ":memory:")` in every test `makeRepo()` helper — never a tmp file path
- `markSaved` / `markIgnored` / `markKnown` MUST NOT be called with `try` at SwiftUI call sites — wrap in `Task { try? ... }`
- `ValueObservation` fires automatically after every write; no manual `NotificationCenter` needed
- `triageStatus` column key in GRDB queries: `Column("triageStatus")` — camelCase, matching the SQL column name exactly (see AGENTS.md GRDB rule)
