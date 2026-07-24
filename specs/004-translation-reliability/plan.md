# Implementation Plan: Translation Reliability

**Branch**: `004-translation-reliability` | **Date**: 2025-07-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-translation-reliability/spec.md`

## Summary

Three distinct bugs compound to produce entries that stay permanently pending and a retry spinner that never stops.

**Bug 1** (`TranslationSessionHost.swift`): `configuration?.invalidate()` is called unconditionally inside every `.translationTask` callback. Per Apple's API, `invalidate()` re-triggers the callback, creating an infinite loop that re-assigns `appleSession` in a tight cycle and may cancel in-flight translation requests. **Fix: delete that single line.**

**Bug 2** (`VocabularyDateGroupSection.swift`): The `.task(id: retryTrigger)` mechanism attaches an async task to a view struct that SwiftUI can recreate on any parent re-render (which happens every time a translation persists to the DB via `ValueObservation`). When recreated, `@State isRetrying` resets mid-flight, corrupting spinner state. **Fix: replace `.task(id:)` with a `Task {}` launched from the button action, stored in `@State var currentRetryTask`.**

**Bug 3** (`VocabularyListView.swift`): `onRetryGroup` passes `group.entries` — a value-type snapshot captured at render time — to `retryGroup(entries:)`. By execution time those entries may already be translated; the service's internal `.pending` filter handles idempotency, but redundant API calls slow the spinner. **Fix: read fresh pending entries from the repository at call time.**

No schema changes are required. The work spans three existing files and removes one line (Bug 1), rewires one SwiftUI task pattern (Bug 2), and updates one closure (Bug 3).

## Technical Context

**Language/Version**: Swift 5.9+, macOS 13+ minimum target

**Primary Dependencies**:
- GRDB.swift 6.29 — persistence and `ValueObservation` for live UI
- Apple `Translation` framework (macOS 15+, conditional import) — on-device EN→FR
- `NWPathMonitor` (Apple `Network` framework) — connectivity-based retry (already in place)
- AppKit + SwiftUI — menu bar app, `NSPopover`-hosted panel

**Storage**: SQLite via GRDB, `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite`. Schema unchanged (no new columns or migrations needed).

**Testing**: Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`). All test targets under `Tests/` (both `Unit/` and `Integration/`).

**Target Platform**: macOS desktop app (menu-bar only, `LSUIElement = YES`, no Dock icon)

**Project Type**: Desktop app (SPM executable target)

**Performance Goals**: Pending entries translate within 5 seconds of session readiness (SC-001). Sequential translation of up to 50 entries is acceptable; parallel translation is out of scope (per spec Assumptions).

**Constraints**:
- `TranslationService.translate(entry:)` must remain non-throwing — do not add `try` at call sites.
- `retryGroup(entries:)` may throw only when `successCount == 0`.
- No new SPM dependencies.
- No schema migrations required.
- Live UI updates via existing GRDB `ValueObservation` — no additional notification infrastructure.

**Scale/Scope**: Single user, typically < 100 pending entries at retry time. The 50-entry sequential ceiling is explicitly accepted in the spec.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project constitution file (`constitution.md`) contains only the placeholder template — no project-specific principles have been ratified. Governance checks are evaluated against the implicit architectural conventions inferred from the existing codebase (AGENTS.md + live code):

| Convention | This Feature | Status |
|---|---|---|
| No new SPM dependencies | No new packages added | ✅ Pass |
| Tests use Swift Testing (`@Suite`, `#expect`) | New tests will follow this pattern | ✅ Pass |
| `translate(entry:)` never throws | Pattern preserved | ✅ Pass |
| GRDB `ValueObservation` for UI updates | Live updates via existing observation — unchanged | ✅ Pass |
| `@MainActor` for delegate callbacks from `CaptureProcessorService` | No new delegate callbacks added | ✅ Pass |
| Localized strings via `L10n.string(_:)` | Any new UI text will use `L10n` | ✅ Pass |
| No new migrations without `"v3"` registration | No schema changes needed | ✅ Pass (N/A) |

**Gate result: PASS.** No violations.

*Post-Phase-1 re-check:* Session lifecycle moved to `AppDelegate` (rather than the view); retry triggered on session readiness and on panel open. No new architectural layers introduced. Convention compliance unchanged — still PASS.

## Project Structure

### Documentation (this feature)

```text
specs/004-translation-reliability/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── contracts/
│   └── translation-service-v2.md   # Updated contract for TranslationService
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
ClipboardVocab/
├── UI/
│   ├── TranslationSessionHost.swift        # MODIFIED — delete configuration?.invalidate() (Bug 1)
│   ├── VocabularyDateGroupSection.swift    # MODIFIED — replace .task(id:) with explicit Task (Bug 2)
│   └── VocabularyListView.swift            # MODIFIED — pass fresh pending entries to retryGroup (Bug 3)
└── [all other files unchanged]

Tests/
└── Unit/
    └── TranslationServiceTests.swift   # unchanged — existing coverage still sufficient
```

**Structure Decision**: Single SPM executable. All changes are surgical modifications to three existing UI files. No new source files, no migrations, no new dependencies.

## Complexity Tracking

No constitution violations. Table not applicable.
