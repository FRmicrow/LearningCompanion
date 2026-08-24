# Implementation Plan: Inbox — Capture & Triage

**Branch**: `007-inbox-capture-triage` | **Date**: 2025-07-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-inbox-capture-triage/spec.md`

---

## Summary

Implement the **Inbox** view as the content of the `.inbox` tab in `VocabularySidebarView` (provided by Epic 1). The view lists vocabulary entries awaiting user triage, hides translations by default, exposes Reveal / Save / Ignore actions (plus swipe gestures), and drives a menu-bar badge from a live GRDB `ValueObservation`. Two new repository methods are needed. One DB migration adds a `triageStatus` column to distinguish `unreviewed` entries from `saved` / `ignored` ones. No new SPM dependencies.

---

## Technical Context

**Language/Version**: Swift 5.9, macOS 13+  
**Primary Dependencies**: SwiftUI, AppKit (`NSStatusItem`), GRDB 6.29+  
**Storage**: SQLite via GRDB — one additive migration (`v3`) to `vocabulary_entries`  
**Testing**: Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`)  
**Target Platform**: macOS 13+ (menu-bar app, `LSUIElement = YES`)  
**Project Type**: Desktop app (SPM executable, no Xcode project)  
**Performance Goals**: Badge updates within 1 s of capture (SC-002); swipe completes within 300 ms (SC-004)  
**Constraints**: All data stays on-device (Constitution I); no new SPM packages (Constitution V)  
**Scale/Scope**: Single user; Inbox likely holds < 50 items at any time

---

## Constitution Check

*Evaluated against constitution version 1.0.1 — ratified 2025-07-18.*

### Gate 1 — Local-First, Privacy-Safe (Principle I)

| Check | Status |
|-------|--------|
| No clipboard or vocabulary data transmitted off-device | ✅ Inbox is a pure local DB view; no network calls |
| Translation backend unchanged (localhost:5001 / on-device) | ✅ TranslationService not modified |
| Triage actions (Save/Ignore/Known) write only to local SQLite | ✅ |

**Gate 1: PASS**

### Gate 2 — Silent, Non-Interruptive Operation (Principle II)

| Check | Status |
|-------|--------|
| No system notifications triggered by triage actions | ✅ |
| Badge on `NSStatusItem` icon is the only passive signal | ✅ No sound, no Dock activity |
| Inbox view only opens on user demand (sidebar toggle) | ✅ |

**Gate 2: PASS**

### Gate 3 — Test-Discipline (Principle III)

| Check | Status |
|-------|--------|
| New repository methods covered by Swift Testing unit tests | ✅ Required — see tasks |
| New `triageStatus` migration covered by DB migration test | ✅ Required |
| Badge count observation covered by unit test | ✅ Required |
| No XCTest introduced | ✅ |

**Gate 3: PASS** — tests are mandatory, not optional.

### Gate 4 — Contract-Driven Service Design (Principle IV)

| Check | Status |
|-------|--------|
| New `InboxView` contract document created before implementation | ✅ Created in Phase 1 |
| `VocabularyEntryRepository` new methods have threading contracts | ✅ Documented in contract |
| GRDB `ValueObservation` remains the exclusive live-update mechanism | ✅ Badge count and list both use `ValueObservation` |
| `TranslationService.translate(entry:)` not called with `try` | ✅ Not touched |

**Gate 4: PASS**

### Gate 5 — Simplicity (Principle V)

| Check | Status |
|-------|--------|
| No new SPM package dependencies | ✅ Swipe gestures implemented with native SwiftUI `.swipeActions` (macOS 13+) |
| Migration is additive (`ALTER TABLE … ADD COLUMN`) | ✅ `triageStatus` column added via `v3` migration |
| No new abstraction layers / patterns introduced | ✅ Inbox view is a SwiftUI `View` following the existing pattern |
| Repository pattern already in use — no new layer required | ✅ |

**Gate 5: PASS**

**Constitution Check Result: ALL GATES PASS. Implementation may proceed.**

---

## Project Structure

### Documentation (this feature)

```text
specs/007-inbox-capture-triage/
├── plan.md              ← this file
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── inbox-view.md
├── checklists/
│   └── requirements.md
└── tasks.md             ← created by /speckit.tasks (not yet)
```

### Source Code

```text
ClipboardVocab/
├── App/
│   └── AppDelegate.swift              — no changes required
├── Models/
│   └── VocabularyEntry.swift          — ADD: TriageStatus enum + triageStatus field
├── Persistence/
│   ├── Database.swift                 — ADD: v3 migration (triageStatus column)
│   └── VocabularyEntryRepository.swift — ADD: fetchInbox(), markSaved(), markIgnored(), markKnown(), fetchInboxCount()
├── UI/
│   ├── InboxView.swift                — NEW: SwiftUI Inbox tab content
│   ├── InboxEntryCard.swift           — NEW: per-entry card (word, reveal, actions)
│   ├── StatusItemController.swift     — MODIFY: add badge update logic + observeBadge()
│   └── VocabularySidebarView.swift    — MODIFY: replace VocabularyListView in .inbox case with InboxView
```

**Structure Decision**: Single SPM executable target, existing `ClipboardVocab/UI/` and `ClipboardVocab/Persistence/` directories. New files follow the one-type-per-file convention established by Epic 1.

---

## Complexity Tracking

No constitution violations identified. No complexity justification needed.
