# Implementation Plan: Vocabulary Panel UI

**Branch**: `002-vocabulary-panel-ui` | **Date**: 2025-07-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-vocabulary-panel-ui/spec.md`

## Summary

Restructure the existing flat `VocabularyListView` popover into a persistent left-anchored panel with three layout zones: (1) date-grouped vocabulary entries with per-group "Retry Translation" buttons and per-entry "ok" checkboxes, (2) an "Old Unretained Words" section showing entries older than 7 days with no retained mark, and (3) an empty-state placeholder when no entries exist. A new `isRetained` boolean column is added to the SQLite schema via GRDB migration. All UI is SwiftUI hosted in the existing `NSPopover`/`NSHostingController` stack; no new frameworks are introduced.

## Technical Context

**Language/Version**: Swift 5.9, macOS 13+

**Primary Dependencies**: SwiftUI (system), GRDB 6.29.x (already in Package.swift), AppKit (NSStatusItem/NSPopover wrapper)

**Storage**: SQLite via GRDB — single file at `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite`. Schema v2 adds `isRetained` column via `DatabaseMigrator`.

**Testing**: XCTest (existing `Tests/` target)

**Target Platform**: macOS 13+ menu-bar application (`.macOS(.v13)` in Package.swift)

**Project Type**: macOS desktop app (menu-bar only, no Dock icon)

**Performance Goals**: Panel renders and displays entries within 1 second of popover open; checkbox toggle updates DB and reflects in UI within one animation frame (~16 ms).

**Constraints**: Single-user, offline-capable, no server process. All DB writes are synchronous on a background queue; UI reads via GRDB `ValueObservation` on `@MainActor`.

**Scale/Scope**: Typical vocabulary list: tens to low hundreds of entries per user. No pagination required for v1.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project's `constitution.md` is a blank template (no project-specific principles have been ratified). No constitution gates apply. ✅

**Post-Phase-1 re-check**: Design adds one schema migration and two new SwiftUI view files. No new dependencies, no new targets, no architectural boundary changes. Constitution remains satisfied. ✅

## Project Structure

### Documentation (this feature)

```text
specs/002-vocabulary-panel-ui/
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── quickstart.md        ← Phase 1 output
├── contracts/
│   └── vocabulary-panel-ui.md  ← Phase 1 output
└── tasks.md             ← Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
ClipboardVocab/
├── App/
│   └── AppDelegate.swift          (no change)
├── Models/
│   └── VocabularyEntry.swift      ← add isRetained: Bool field
├── Persistence/
│   ├── Database.swift             ← register v2 migration (isRetained column)
│   └── VocabularyEntryRepository.swift  ← add markRetained(id:_:) + fetchOldUnretained()
├── Services/
│   └── TranslationService.swift   ← add retryGroup(entries:) method
└── UI/
    ├── VocabularyListView.swift    ← replace flat list with grouped + old-words layout
    ├── VocabularyDateGroupSection.swift  ← NEW: date-group header + rows
    ├── VocabularyEntryRow.swift    ← add isRetained checkbox; remove standalone retry button (moved to group header)
    ├── OldUnretainedWordsSection.swift   ← NEW: separate section for aged unretained entries
    └── EmptyStateView.swift       (no change)

Tests/
└── (unit tests for repository methods and date-grouping logic)
```

**Structure Decision**: Single-target macOS app. Feature adds two new SwiftUI view files (`VocabularyDateGroupSection`, `OldUnretainedWordsSection`) and modifies three existing files (`VocabularyEntry`, `Database`, `VocabularyEntryRepository`, `VocabularyListView`, `VocabularyEntryRow`). No new SPM targets, no new dependencies.

## Complexity Tracking

> No constitution violations. Section left intentionally empty.
