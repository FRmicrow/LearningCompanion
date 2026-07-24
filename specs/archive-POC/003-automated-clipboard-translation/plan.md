# Implementation Plan: Automated Clipboard Translation

**Branch**: `003-automated-clipboard-translation` | **Date**: 2025-07-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-automated-clipboard-translation/spec.md`

---

## Summary

Build a macOS menu bar application that silently monitors the system clipboard every 500 ms, detects English text, filters out noise (URLs, numbers, file paths, text > 50 chars), and translates eligible words and short phrases to French using an on-device or HTTP translation backend. Captured entries are persisted in a local SQLite database with full deduplication and offline-retry support. The user can pause and resume capture via a global keyboard shortcut (⌘ Shift C) or the menu bar context menu.

This feature is the **foundational pipeline** of ClipboardVocab — all other features (vocabulary panel, retained words, etc.) depend on it producing data.

---

## Technical Context

**Language/Version**: Swift 5.9+

**Primary Dependencies**:
- `AppKit` — `NSStatusItem`, `NSPopover`, `NSPasteboard` (all bundled with macOS)
- `NaturalLanguage` — `NLLanguageRecognizer` for on-device language detection
- `Network` — `NWPathMonitor` for connectivity-change retry
- `Carbon` / `KeyboardShortcuts` (sindresorhus) — global ⌘ Shift C hotkey registration
- `GRDB.swift 6.x` — SQLite persistence and `ValueObservation` for live UI updates
- `Translation` framework (macOS 15+, optional) — on-device EN→FR neural translation
- LibreTranslate HTTP endpoint — fallback for macOS 13–14

**Storage**: SQLite via GRDB.swift — `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite`

**Testing**: XCTest / Swift Testing; in-memory GRDB `DatabaseQueue` for repository tests

**Target Platform**: macOS 13 Ventura or later (no Dock icon, `LSUIElement = YES`)

**Project Type**: Desktop menu bar app (macOS-only)

**Performance Goals**:
- Capture latency ≤ 3 s end-to-end (SC-001)
- CPU < 1% at idle over 10-minute observation (SC-005)
- RAM < 50 MB

**Constraints**:
- No internet required for core capture (language detection is on-device)
- No user account or cloud sync — fully local
- Accessibility permission required for global hotkey (documented)
- Pause state is never persisted across restarts

**Scale/Scope**: Single user, single device; hundreds to low thousands of vocabulary entries

---

## Constitution Check

*The project does not have a custom constitution. Standard engineering principles apply.*

Gates evaluated against spec requirements:

| Gate | Status | Notes |
|------|--------|-------|
| All user stories independently testable | ✅ | Each story has an independent test scenario in spec.md |
| No implementation details in spec | ✅ | spec.md is technology-agnostic |
| Success criteria are measurable | ✅ | SC-001 through SC-006 all have concrete metrics |
| Dependencies justified | ✅ | All dependencies documented in research.md with alternatives |
| No duplicate architectural concerns with spec 001 | ✅ | This spec covers the same pipeline — treated as the formal document for the already-implemented feature |

---

## Project Structure

### Documentation (this feature)

```text
specs/003-automated-clipboard-translation/
├── plan.md              # This file
├── research.md          # Phase 0 — technology decisions
├── data-model.md        # Phase 1 — entity schema, state machines
├── quickstart.md        # Phase 1 — validation scenarios
├── contracts/           # Phase 1 — service interface contracts
│   ├── clipboard-monitor.md
│   ├── capture-processor.md
│   └── translation-service.md
└── tasks.md             # Phase 2 output (via /speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
ClipboardVocab/
├── App/
│   ├── main.swift                        # NSApplication entry point
│   ├── AppDelegate.swift                 # Service wiring, connectivity monitor, hotkey
│   └── Info.plist                        # LSUIElement = YES
├── Models/
│   ├── VocabularyEntry.swift             # GRDB record + TranslationStatus enum
│   └── CaptureState.swift                # .active / .paused
├── Persistence/
│   ├── Database.swift                    # DatabaseQueue + migrations
│   └── VocabularyEntryRepository.swift  # upsert / update / delete / fetch*
├── Services/
│   ├── ClipboardMonitorService.swift     # 500 ms NSPasteboard polling
│   ├── CaptureProcessorService.swift     # Full filter pipeline
│   ├── LanguageDetectionService.swift    # NLLanguageRecognizer wrapper
│   ├── TranslationService.swift          # LibreTranslate HTTP + Apple Translation
│   └── GlobalShortcutManager.swift       # Carbon RegisterEventHotKey (⌘ Shift C)
└── UI/
    ├── StatusItemController.swift        # NSStatusItem + NSPopover lifecycle
    ├── VocabularyListView.swift          # SwiftUI List, GRDB ValueObservation
    ├── VocabularyEntryRow.swift          # Per-entry row with retry + delete
    └── EmptyStateView.swift              # French empty-state

Tests/
├── Unit/
│   ├── VocabularyEntryRepositoryTests.swift
│   ├── CaptureProcessorTests.swift
│   └── LanguageDetectionTests.swift
└── Integration/
    └── CaptureToStorageTests.swift       # End-to-end timing (SC-001 guard)
```

**Structure Decision**: Single-project Swift Package Manager structure. No monorepo splitting warranted — all code is macOS-only, tightly integrated, and shares a single data layer.
