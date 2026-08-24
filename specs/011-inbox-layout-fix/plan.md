# Implementation Plan: Inbox Layout Fix

**Branch**: `011-inbox-layout-fix` | **Date**: 2025-08-24 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-inbox-layout-fix/spec.md`

## Summary

Remove the hard-coded `frame(width: 380)` and `frame(maxHeight: 500)` constraints from
`VocabularyListView`. These two modifiers prevent the Inbox list from filling the full
panel height and force the content area to a width (380 pt) wider than the panel (340 pt),
causing a layout overflow that pushes the `SidebarTabBar` partially off-screen. The fix is
a two-line change in `VocabularyListView`; no DB changes, no new dependencies.

## Technical Context

**Language/Version**: Swift 5.9, macOS 13+

**Primary Dependencies**: SwiftUI, GRDB (existing)

**Storage**: N/A (no schema changes)

**Testing**: Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`)

**Target Platform**: macOS 13+ desktop app (menu bar, `NSPanel`)

**Project Type**: Desktop app — `VocabularySidebarPanel` is a borderless `NSPanel`
(340 pt wide, full `visibleFrame.height` tall) hosting a `NSHostingController<VocabularySidebarView>`.

**Performance Goals**: No performance impact — pure layout change.

**Constraints**: Panel width fixed at 340 pt (C-02 in `vocabulary-sidebar.md`). All existing
threading contracts unchanged.

**Scale/Scope**: Two-file change; one SwiftUI view (`VocabularyListView`). No migrations,
no new contracts, no new tests unless a regression-guard test is desired.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Local-First, Privacy-Safe | ✅ Pass | No network calls; no data model change. |
| II — Silent, Non-Interruptive Operation | ✅ Pass | Pure layout change; no notifications or user interruptions. |
| III — Test-Discipline | ✅ Pass | No new logic introduced; regression covered by manual quickstart scenario. |
| IV — Contract-Driven Service Design | ✅ Pass | No public API change; contract C-02/C-06 still respected. No contract amendment needed — the fix aligns implementation with the already-documented 340 pt width contract. |
| V — Simplicity — No Unjustified Complexity | ✅ Pass | Change reduces complexity (removes hard-coded magic numbers). No new dependencies. |
| SC-001 Capture latency ≤ 3,000 ms | ✅ Pass | Unaffected. |
| Background CPU/RAM | ✅ Pass | Unaffected. |

**Constitution Check result**: All gates pass. No violations to justify in Complexity Tracking.

*Post-design re-check*: After Phase 1 — unchanged. The fix is a strict subset of the
layout constraints already documented in C-02; no gate failures.

## Project Structure

### Documentation (this feature)

```text
specs/011-inbox-layout-fix/
├── plan.md              ← this file
├── research.md          ← Phase 0 (root-cause analysis)
├── data-model.md        ← Phase 1 (no entity changes; documents layout model)
├── quickstart.md        ← Phase 1 (manual validation guide)
├── contracts/           ← Phase 1 (amendment note to vocabulary-sidebar.md)
└── tasks.md             ← Phase 2 (/speckit.tasks — not created here)
```

### Source Code (affected files only)

```text
ClipboardVocab/UI/
└── VocabularyListView.swift   ← remove .frame(width: 380) and .frame(maxHeight: 500)
```

**Structure Decision**: Single project (no monorepo). Only one SwiftUI file changes.
The `NSPanel` sizing lives in `VocabularySidebarPanel.swift` (unchanged; already correct).

## Complexity Tracking

> No Constitution Check violations — table intentionally empty.
