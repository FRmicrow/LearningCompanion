---
description: "Task list for 011-inbox-layout-fix"
---

# Tasks: Inbox Layout Fix

**Input**: Design documents from `specs/011-inbox-layout-fix/`

**Prerequisites**: [plan.md](plan.md) · [spec.md](spec.md) · [research.md](research.md) · [data-model.md](data-model.md) · [contracts/vocabulary-list-layout.md](contracts/vocabulary-list-layout.md) · [quickstart.md](quickstart.md)

**Tests**: Not requested — this is a pure layout change with no new logic. Validation is manual via `quickstart.md` scenarios.

**Organization**: Both user stories (US1 full-height list, US2 fully-visible tab bar) are caused by the same three frame modifiers in one file. They are implemented together in a single phase with no shared foundational prerequisites.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other `[P]` tasks in the same phase
- **[Story]**: User story this task belongs to
- Exact file path included in every task

---

## Phase 1: Setup

**Purpose**: Confirm the panel width constant and existing layout contracts are understood before touching the view.

- [ ] T001 Read `ClipboardVocab/UI/VocabularySidebarPanel.swift` and confirm `width` constant is `340` (C-02) — no code change, just a pre-flight check
- [ ] T002 Read `ClipboardVocab/UI/VocabularyListView.swift` lines 134–174 and locate the three frame modifiers to be removed/replaced

**Checkpoint**: Both files read; exact line numbers for the three modifiers confirmed.

---

## Phase 2: User Stories 1 & 2 — Full-height list + Fully-visible tab bar (Priority: P1) 🎯 MVP

Both user stories are fixed by the same three-line change in `VocabularyListView`.

**Goal (US1)**: The Inbox word list expands to fill all available vertical space — no empty gap between the last row and the tab bar.

**Goal (US2)**: All four tab bar buttons (Inbox, Learn, Review, Statistics) are fully visible and unclipped at the default panel size.

**Independent Test**: Open the panel → navigate to Inbox → confirm list fills height and all four tab buttons are fully visible (quickstart.md Scenarios 1, 2, 3, 4).

### Implementation

- [ ] T003 [US1] [US2] In `ClipboardVocab/UI/VocabularyListView.swift`: replace `.frame(width: 380, height: 200)` on `EmptyStateView` with `.frame(maxWidth: .infinity, maxHeight: .infinity)` (line ~136)
- [ ] T004 [US1] [US2] In `ClipboardVocab/UI/VocabularyListView.swift`: replace `.frame(width: 380)` on the `List` with `.frame(maxWidth: .infinity)` (line ~170)
- [ ] T005 [US1] [US2] In `ClipboardVocab/UI/VocabularyListView.swift`: remove `.frame(maxHeight: 500)` from the `List` entirely (line ~171)
- [ ] T006 Build the project — `swift build` — confirm zero new errors or warnings

**Checkpoint**: Build passes. Open the panel and run all four quickstart.md scenarios manually.

---

## Phase 3: Polish & Validation

**Purpose**: Manual validation, spec artifact update, and contract annotation.

- [x] T007 Run `quickstart.md` Scenario 1 — Inbox list fills panel height with ≥ 10 entries
- [ ] T008 Run `quickstart.md` Scenario 2 — All four tab bar buttons fully visible
- [ ] T009 Run `quickstart.md` Scenario 3 — Empty-state placeholder centred in full content area
- [ ] T010 Run `quickstart.md` Scenario 4 — No regression on Learn, Review, Stats tabs
- [ ] T011 [P] Run `swift test` — confirm all existing tests still pass (no regressions)
- [ ] T012 [P] Update `ClipboardVocab/UI/VocabularyListView.swift` doc-comment (line 4–11) to note that the `List` is unconstrained and inherits its size from `VocabularySidebarView` (per C-24/C-25)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Phase 2 (US1 & US2)**: Depends on Phase 1 completion (understand exact lines)
- **Polish (Phase 3)**: Depends on Phase 2 build passing

### User Story Dependencies

- **US1 and US2** share the same implementation tasks (T003–T006) — they cannot be split across developers; complete together.

### Within Phase 2

- T003, T004, T005 are all edits to the same file — do them sequentially in one editing session
- T006 (`swift build`) must follow T003–T005

### Parallel Opportunities

- T011 (`swift test`) and T012 (doc-comment update) in Phase 3 can run in parallel once T010 passes

---

## Parallel Example: Phase 2

```text
# These three edits are to the same file — do sequentially:
T003: Fix EmptyStateView frame  →  T004: Fix List width  →  T005: Remove List height cap

# Then build-verify:
T006: swift build
```

---

## Implementation Strategy

### MVP (the only scope here)

1. Complete Phase 1: read the two files, confirm line numbers
2. Complete Phase 2: three targeted edits + `swift build`
3. Complete Phase 3: run four manual quickstart scenarios + `swift test`
4. **Done** — no further stories, no follow-on work

### Key Constraints (from contracts/)

- Panel width stays at **340 pt** (C-02 — do not touch `VocabularySidebarPanel.swift`)
- New contracts C-24, C-25, C-26 (in `specs/011-inbox-layout-fix/contracts/vocabulary-list-layout.md`) are satisfied by these tasks
- No DB migrations, no new dependencies, no new tests required

---

## Notes

- All three frame modifiers are in `ClipboardVocab/UI/VocabularyListView.swift` — no other file changes
- `VocabularySidebarPanel.swift` and `VocabularySidebarView.swift` are already correct; do not modify them
- `swift test` already covers all service-layer logic; no new test files needed for a layout-only change
- Commit after T006 (build green) and again after T011 (tests green)
