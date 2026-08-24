# Implementation Plan: Inbox Word Management & Learn Session Control

**Branch**: `010-inbox-word-management` | **Date**: 2025-07-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-inbox-word-management/spec.md`

---

## Summary

Extend the Inbox tab with multi-select capability (bulk delete + promote to Learn), extend the Learn session with a Restart action (random 20-sample when pool > 20), and implement Easy = mastered: rating a word Easy in Learn mode permanently retires it from all future queues. Backed by a single additive GRDB migration (v6) adding an `isMastered` boolean column, three new repository methods, and targeted extensions to `FocusSession` and the existing Learn view.

---

## Technical Context

**Language/Version**: Swift 5.9, macOS 13+

**Primary Dependencies**: GRDB (SQLite persistence + ValueObservation), SwiftUI (macOS popover UI)

**Storage**: SQLite via GRDB `DatabaseQueue`; in-memory `":memory:"` for all tests

**Testing**: Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) — XCTest MUST NOT be introduced

**Target Platform**: macOS 13+ menu-bar application (`LSUIElement = YES`)

**Project Type**: macOS desktop app (SPM, no Xcode project file)

**Performance Goals**: Batch delete and mastery write must not measurably affect the ≤ 3,000 ms capture-to-DB latency (SC-001 in `CaptureToStorageTests`)

**Constraints**: < 50 MB background RAM; < 1% background CPU; all writes on background thread via `Task`; all UI state mutations on `@MainActor`

**Scale/Scope**: Single-user, single-machine; vocabulary tables expected to have < 10,000 rows; selection state holds < 100 IDs at any time

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### I. Local-First, Privacy-Safe ✅

All new state (`isMastered`, selection state) is local-only SQLite. No data is transmitted off-device. No new network calls are introduced. The `markMastered` and `deleteAll` writes target the same local `DatabaseQueue`. **PASS**.

### II. Silent, Non-Interruptive Operation ✅

Selection mode and the Restart action operate entirely within the existing `NSPopover` panel. No notifications, sounds, or new OS-level surfaces are introduced. Mastery does not surface a system notification. **PASS**.

### III. Test-Discipline (NON-NEGOTIABLE) ✅

All new logic — mastery exclusion, batch delete, random sampling, `isMastered` migration — is covered by dedicated Swift Testing suites in `Tests/Unit/`. XCTest is not used. The existing `CaptureToStorageTests` SC-001 timing test is not modified. **PASS**.

### IV. Contract-Driven Service Design ✅

A new `contracts/inbox-word-management.md` defines all new method signatures, threading contracts, and column ownership rules. `applyRating` contract is not modified (mastery is a separate `markMastered` call). `FocusSession` gains one new `let` field (`isOnDemand`) without changing any existing method signature. **PASS**.

### V. Simplicity — No Unjustified Complexity ✅

- No new SPM dependencies. Random sampling uses `Array.shuffled()` from the Swift standard library.
- No new architectural layer (no view model, no coordinator). Selection state lives in `@State`.
- One new migration (`v6`) with a single `ALTER TABLE`. Additive-only.
- Three new repository methods following the established single-column-UPDATE pattern.
- `isOnDemand` on `FocusSession` is a single `Bool` — zero new types.

**PASS — no Complexity Tracking entries required.**

---

## Project Structure

### Documentation (this feature)

```text
specs/010-inbox-word-management/
├── plan.md              ← This file
├── spec.md              ← Feature specification
├── research.md          ← Phase 0: 8 decisions
├── data-model.md        ← Phase 1: migration v6, model changes, new queries
├── quickstart.md        ← Phase 1: 9 automated + 7 manual validation scenarios
├── contracts/
│   └── inbox-word-management.md  ← Phase 1: 62 contracts
├── checklists/
│   └── requirements.md  ← Spec quality checklist (all pass)
└── tasks.md             ← Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
ClipboardVocab/
├── Models/
│   ├── VocabularyEntry.swift          # Add isMastered: Bool field + CodingKey
│   └── FocusSession.swift             # Add isOnDemand: Bool field
├── Persistence/
│   ├── Database.swift                 # Register migration v6
│   └── VocabularyEntryRepository.swift # Add fetchLearnPool(), markMastered(id:), deleteAll(ids:)
│                                       # Update fetchDueEntries() + fetchDueCount() with isMastered filter
└── UI/
    ├── VocabularyListView.swift        # Selection mode, Delete Selected, Add to Learn
    ├── VocabularySidebarView.swift     # Thread session binding + tab-switch callback to Inbox
    ├── LearnView.swift                 # Restart action, mastery write on Easy, on-demand session init
    └── SessionCompletionView.swift     # Add Restart Session button

Tests/Unit/
├── DatabaseMigrationV6Tests.swift     # New: v6 column smoke-test
├── InboxSelectionTests.swift          # New: deleteAll, empty-ids, selection state
├── LearnSessionRestartTests.swift     # New: pool sizing, random sampling
├── MasteryTests.swift                 # New: Easy rating → isMastered, queue exclusion
└── VocabularyEntryRepositoryTests.swift # Existing: extend with new method tests
```

**Structure Decision**: Single-project SPM layout (Option 1). All new files are co-located with existing files in their respective module folders. No new top-level directories.

---

## Complexity Tracking

> No Constitution Check violations found. No entries required.
