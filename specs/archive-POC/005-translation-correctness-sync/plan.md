# Implementation Plan: Translation Correctness & Sync

**Branch**: `005-translation-correctness-sync` | **Date**: 2025-07-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-translation-correctness-sync/spec.md`

## Summary

This feature defines and locks the correct, stable end-to-end translation behaviour for ClipboardVocab. The three session/spinner/snapshot bugs documented in `specs/004-translation-reliability` have already been fixed in the current codebase. This plan's job is to:

1. Confirm the existing implementation satisfies every requirement in spec 005 with no gaps.
2. Identify and close the one remaining reliability gap: `retryPendingTranslations()` has no concurrency guard — concurrent callers (session-ready callback, connectivity-restored handler, manual retry) can race each other and schedule redundant sequential translation passes.
3. Produce contracts and validation materials that represent the ratified, stable behaviour going forward.

**The fix is minimal**: add an `isRetrying: Bool` actor-isolated flag (or a `Task?` reference) to `TranslationService` so that if a retry is already in flight, new triggers are dropped rather than queued. This satisfies FR-009 and SC-005 from the spec without altering the public interface.

## Technical Context

**Language/Version**: Swift 5.9+, macOS 13+ minimum target

**Primary Dependencies**:
- GRDB.swift 6.29 — persistence and `ValueObservation` for live UI
- Apple `Translation` framework (macOS 15+, conditional import) — on-device EN→FR
- `NWPathMonitor` (Apple `Network` framework) — connectivity-based retry (already in place)
- AppKit + SwiftUI — menu bar app, `NSPopover`-hosted panel

**Storage**: SQLite via GRDB, `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite`. Schema unchanged — no new columns or migrations needed.

**Testing**: Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`). All test targets under `Tests/` (both `Unit/` and `Integration/`).

**Target Platform**: macOS desktop app (menu-bar only, `LSUIElement = YES`, no Dock icon)

**Project Type**: Desktop app (SPM executable target)

**Performance Goals**: Pending entries translate within 10 seconds of session readiness (SC-001). Sequential translation of up to ~100 entries is acceptable; parallel translation is out of scope.

**Constraints**:
- `TranslationService.translate(entry:)` MUST remain non-throwing — never add `try` at call sites.
- `retryGroup(entries:)` MUST throw only when `successCount == 0`.
- No new SPM dependencies.
- No schema migrations required.
- Live UI updates via existing GRDB `ValueObservation` — no additional notification infrastructure.
- All new logic MUST be covered by Swift Testing tests (`import Testing`, `@Suite`, `@Test`, `#expect`).

**Scale/Scope**: Single user, single machine. Typically < 100 pending entries at retry time.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Convention | This Feature | Status |
|---|---|---|
| Local-first, privacy-safe — no external data transmission | No new network calls; all translation uses existing on-device or localhost path | ✅ Pass |
| No new SPM dependencies | No new packages added | ✅ Pass |
| Tests use Swift Testing (`@Suite`, `#expect`) — XCTest MUST NOT be introduced | New test for concurrency guard will follow Swift Testing | ✅ Pass |
| `translate(entry:)` never throws | Preserved — not changed | ✅ Pass |
| `retryGroup(entries:)` throws only when `successCount == 0` | Preserved — not changed | ✅ Pass |
| GRDB `ValueObservation` is the exclusive live-UI mechanism | Unchanged | ✅ Pass |
| `@MainActor` for `CaptureProcessorService` delegate callbacks | No new delegate callbacks added | ✅ Pass |
| Localized strings via `L10n.string(_:)` | No new user-facing strings added | ✅ Pass |
| No new migrations without `"v3"` registration | No schema changes needed | ✅ Pass (N/A) |
| Concurrency guard respects `translate(entry:)` never-throws rule | The `isRetrying` flag is only inside `retryPendingTranslations()` — does not affect `translate(entry:)` contract | ✅ Pass |

**Gate result: PASS.** No violations.

*Post-Phase-1 re-check:* Concurrency guard added to `retryPendingTranslations()` only, using an `actor`-isolated or `@MainActor`-coordinated flag. No new abstractions, no new files beyond a contract amendment and test. Constitution compliance unchanged — still PASS.

## Project Structure

### Documentation (this feature)

```text
specs/005-translation-correctness-sync/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── translation-service-v3.md   # Phase 1 output — amends v2 with concurrency guard
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
ClipboardVocab/
└── Services/
    └── TranslationService.swift    # MODIFIED — add concurrency guard to retryPendingTranslations()

Tests/
└── Unit/
    └── TranslationServiceTests.swift   # MODIFIED — add test for concurrency guard
```

**Structure Decision**: Single SPM executable. One surgical change to one existing service file, plus one new test. No new source files, no migrations, no new dependencies.

## Complexity Tracking

No constitution violations. Table not applicable.
