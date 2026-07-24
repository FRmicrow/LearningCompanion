# Implementation Plan: Clipboard Vocabulary Capture

**Branch**: `001-clipboard-vocab-capture` | **Date**: 2025-07-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-clipboard-vocab-capture/spec.md`

## Summary

Build a macOS menu bar application (Swift + AppKit, macOS 13+) that silently monitors the clipboard via 0.5-second `NSPasteboard` polling, uses Apple's `NLLanguageRecognizer` to detect English text (≤ 50 chars), translates it to French via Apple's `Translation` framework (macOS 15+) or a LibreTranslate fallback, and persists entries in a local SQLite database (GRDB.swift). The user interacts through an `NSPopover` vocabulary panel and a Command+Shift+C global shortcut to pause/resume capture.

## Technical Context

**Language/Version**: Swift 5.9 — macOS 13.0 (Ventura) minimum target

**Primary Dependencies**:
- `GRDB.swift` — SQLite persistence (SPM)
- `KeyboardShortcuts` (sindresorhus) — global hotkey registration (SPM)
- Apple `NaturalLanguage` framework — on-device language detection (bundled with macOS)
- Apple `Translation` framework — on-device EN→FR translation (macOS 15+; LibreTranslate HTTP fallback for macOS 13–14)

**Storage**: SQLite (single file at `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite`) — see [data-model.md](data-model.md)

**Testing**: XCTest (unit + integration); UI validation via [quickstart.md](quickstart.md) manual scenarios

**Target Platform**: macOS 13.0+ (arm64 + x86_64 universal binary)

**Project Type**: macOS menu bar desktop application (no Dock icon, `LSUIElement = YES`)

**Performance Goals**: Capture latency ≤ 3s (SC-001); UI open ≤ 2s (SC-004)

**Constraints**: < 1% CPU idle, < 50 MB RAM (SC-003); local storage only (no cloud); no runtime dependencies beyond SPM packages

**Scale/Scope**: Single-user, single-machine; vocabulary list potentially thousands of entries; no multi-user, no sync

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution template has not been filled for this project — no project-specific governance constraints are in force. No gate violations to record.

**Post-design re-check**: All design decisions (Swift native, GRDB, on-device NLP, local-only storage) align with the spec's stated constraints. No complexity violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-clipboard-vocab-capture/
├── spec.md           # Feature specification
├── plan.md           # This file
├── research.md       # Phase 0: technology decisions and rationale
├── data-model.md     # Phase 1: VocabularyEntry schema, state transitions, indexes
├── quickstart.md     # Phase 1: end-to-end validation scenarios
├── contracts/
│   ├── vocabulary-list-ui.md    # UI contract: panel display, entry rows, empty state
│   ├── capture-processor.md     # Service contract: filter pipeline + translation retry
│   └── clipboard-monitor.md     # Service contract: NSPasteboard polling interface
└── tasks.md          # Phase 2 output (/speckit.tasks command — NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
ClipboardVocab/
├── App/
│   ├── AppDelegate.swift          # NSStatusItem setup, app lifecycle, LSUIElement config
│   └── Info.plist                 # LSUIElement = YES, required entitlements
├── Services/
│   ├── ClipboardMonitorService.swift    # NSPasteboard polling, pause/resume, CaptureState
│   ├── CaptureProcessorService.swift   # Full filter pipeline (length, language, dedup, translate)
│   ├── LanguageDetectionService.swift  # NLLanguageRecognizer wrapper (confidence threshold 0.6)
│   └── TranslationService.swift        # Translation framework + LibreTranslate fallback + retry queue
├── Persistence/
│   ├── Database.swift                  # GRDB setup, migrations, user_version management
│   └── VocabularyEntryRepository.swift # CRUD + upsert (dedup insert/update)
├── Models/
│   ├── VocabularyEntry.swift           # Codable + FetchableRecord + PersistableRecord
│   └── CaptureState.swift              # enum .active / .paused
├── UI/
│   ├── StatusItemController.swift      # NSStatusItem + NSPopover lifecycle, icon state
│   ├── VocabularyListView.swift        # SwiftUI List of VocabularyEntryRow views
│   ├── VocabularyEntryRow.swift        # Single row: English, translation/pending badge, seen count, delete
│   └── EmptyStateView.swift            # Empty list placeholder (FR message)
└── Resources/
    ├── Assets.xcassets                 # Menu bar icon (active + paused variants)
    └── Localizable.strings             # FR strings (empty state, labels)

Tests/
├── Unit/
│   ├── CaptureProcessorTests.swift     # Pipeline gate logic (length, language, dedup)
│   ├── LanguageDetectionTests.swift    # EN/FR/other/low-confidence detection
│   └── VocabularyEntryRepositoryTests.swift  # Insert, upsert, delete, counter increment
└── Integration/
    └── CaptureToStorageTests.swift     # ClipboardMonitor → CaptureProcessor → DB round trip
```

**Structure Decision**: Single-project macOS app. Services are plain Swift classes (no framework separation needed for a single-screen menu bar app). UI layer uses SwiftUI embedded in an `NSPopover`; the rest of the app uses AppKit directly for system integration.

## Complexity Tracking

> No constitution violations to justify. No entry required.
