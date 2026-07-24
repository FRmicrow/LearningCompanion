# Implementation Plan: Vocabulary Sidebar — Native Panel

**Branch**: `006-vocabulary-sidebar` | **Date**: 2025-07-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-vocabulary-sidebar/spec.md`

---

## Summary

Replace the existing `NSPopover`-based vocabulary list with a non-activating `NSPanel` floating sidebar anchored to the right edge of the primary display. The panel hosts a SwiftUI root view (`VocabularySidebarView`) with a bottom tab bar (Inbox / Learn / Review / Stats), a daily progress bar, and panel-scoped keyboard shortcuts. No database migrations are required. The global hotkey is rewired from capture-state toggle to sidebar toggle.

---

## Technical Context

**Language/Version**: Swift 5.9, macOS 13+  
**Primary Dependencies**: AppKit (`NSPanel`), SwiftUI, GRDB 6.29+  
**Storage**: SQLite via GRDB (existing `vocabulary_entries` table — read-only for this epic)  
**Testing**: Swift Testing (`import Testing`, `@Suite`, `@Test`)  
**Target Platform**: macOS 13+ (menu-bar app, `LSUIElement = YES`)  
**Project Type**: Desktop app (SPM executable, no Xcode project)  
**Performance Goals**: Panel visible within 100 ms of hotkey press  
**Constraints**: Panel must never activate the owning app / steal key focus  
**Scale/Scope**: Single user, single display, ≤ a few hundred vocabulary entries

---

## Constitution Check

No `.specify/memory/constitution.md` found — skipping gate evaluation.

**Self-check against AGENTS.md rules**:

| Rule | Status |
|------|--------|
| `TranslationService.translate(entry:)` never throws — no `try` at call site | ✅ Not touched by this epic |
| GRDB `Column("fieldName")` keys match SQL camelCase column names | ✅ No new queries introduce new column keys |
| `GlobalShortcutManager` singleton must stay alive for app lifetime | ✅ Singleton unchanged; only its `action` closure is rewired |
| `CaptureProcessorService` delegate methods are `@MainActor` | ✅ Not touched by this epic |
| `VocabularyListView` ValueObservation pattern — `Task { @MainActor }` + cancel on `onDisappear` | ✅ New `DailyProgress` observation follows same pattern |
| All localised strings via `L10n.string(_:)` | ✅ Any new UI strings must use `L10n.string(_:)` |
| `VocabularyEntryRepository.dbQueue` is `internal` — do not tighten | ✅ Not changed |
| `TranslationSessionHost.install(translationService:)` wiring unchanged | ✅ Not touched |

---

## Project Structure

### Documentation (this feature)

```text
specs/006-vocabulary-sidebar/
├── plan.md              ← this file
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── vocabulary-sidebar.md
├── checklists/
│   └── requirements.md
└── tasks.md             ← created by /speckit.tasks (not yet)
```

### Source Code

```text
ClipboardVocab/
├── App/
│   └── AppDelegate.swift            ← rewire GlobalShortcutManager action
├── UI/
│   ├── VocabularySidebarPanel.swift  ← NEW: NSPanel wrapper
│   ├── VocabularySidebarView.swift   ← NEW: SwiftUI root view + tab bar + progress
│   ├── SidebarTabBar.swift           ← NEW: bottom tab bar component
│   ├── DailyProgressBar.swift        ← NEW: progress header component
│   ├── StatusItemController.swift    ← MODIFIED: replace NSPopover with panel
│   └── VocabularyListView.swift      ← MODIFIED: becomes Inbox tab child
```

**Structure Decision**: Single SPM executable target, existing `ClipboardVocab/UI/` directory. New files slot directly into that directory following the existing naming convention (one type per file, type name = file name).

---

## Complexity Tracking

No constitution violations identified. No complexity justification needed.
