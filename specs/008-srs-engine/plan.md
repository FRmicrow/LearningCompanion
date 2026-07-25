# Implementation Plan: SRS Engine — Spaced Repetition

**Branch**: `008-srs-engine` | **Date**: 2025-07-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-srs-engine/spec.md`

---

## Summary

Implement the **SRS Engine** as a pure scheduling service (`SRSEngine`) plus a DB migration (`v4`) that adds five new columns to `vocabulary_entries`. The engine applies the SM-2 algorithm to compute new review intervals and states. A new repository method (`applyRating`) writes the update atomically. Two new reactive queries (`fetchDueEntries`, `fetchDueCount`) expose the daily review queue to Epic 4 (Learn/Review) and Epic 1 (daily progress bar). The existing `markSaved` method is extended to seed SRS defaults on Inbox save. No new SPM dependencies.

---

## Technical Context

**Language/Version**: Swift 5.9, macOS 13+  
**Primary Dependencies**: GRDB 6.29+  
**Storage**: SQLite via GRDB — one additive migration (`v4`) to `vocabulary_entries`  
**Testing**: Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`)  
**Target Platform**: macOS 13+ (menu-bar app, `LSUIElement = YES`)  
**Performance Goals**: Rating write within 100 ms (F-304); queue observation update within 500 ms (SC-1)  
**Constraints**: All data stays on-device (Constitution I); no new SPM packages (Constitution V)  
**Scale/Scope**: Single user; vocabulary set expected to be < 2,000 entries; daily queue typically < 50 items

---

## Constitution Check

*Evaluated against constitution version 1.0.1 — ratified 2025-07-18.*

### Gate 1 — Local-First, Privacy-Safe (Principle I)

| Check | Status |
|-------|--------|
| SRS fields stored exclusively in local SQLite | ✅ No network calls; no off-device transmission |
| `SRSEngine` is a pure local function; no HTTP requests | ✅ |
| `applyRating` writes only to local `DatabaseQueue` | ✅ |

**Gate 1: PASS**

### Gate 2 — Silent, Non-Interruptive Operation (Principle II)

| Check | Status |
|-------|--------|
| SRS scheduling produces no system notifications | ✅ |
| `ValueObservation` fires silently in background | ✅ No UI interruption |
| No new modal dialogs or system alerts from the engine layer | ✅ |

**Gate 2: PASS**

### Gate 3 — Test-Discipline (Principle III)

| Check | Status |
|-------|--------|
| `SRSEngine.rate` covered by pure unit tests for all four ratings | ✅ Required |
| State transition thresholds tested (new→learning, learning→known, known→mastered) | ✅ Required |
| `applyRating` repository method covered by in-memory DB tests | ✅ Required |
| `fetchDueEntries` / `fetchDueCount` covered with known `dueDate` test fixtures | ✅ Required |
| Migration `v4` tested: existing rows unaffected, new columns present | ✅ Required |
| Write failure path tested via injected DB error | ✅ Required |
| No XCTest introduced | ✅ |

**Gate 3: PASS** — tests are mandatory, not optional.

### Gate 4 — Contract-Driven Service Design (Principle IV)

| Check | Status |
|-------|--------|
| `SRSEngine` contract document created before implementation | ✅ Created in Phase 1 |
| `VocabularyEntryRepository` new methods have threading contracts | ✅ Documented in contract (C-41 through C-45) |
| GRDB `ValueObservation` remains the exclusive live-update mechanism | ✅ `fetchDueEntries` and `fetchDueCount` both use `ValueObservation` |
| `TranslationService.translate(entry:)` not called with `try` | ✅ Not touched by this epic |
| `SRSEngine.rate` is declared non-throwing (pure function) | ✅ |

**Gate 4: PASS**

### Gate 5 — Simplicity (Principle V)

| Check | Status |
|-------|--------|
| No new SPM package dependencies | ✅ SM-2 implemented as a pure Swift function; no library needed |
| Migration is additive (`ALTER TABLE … ADD COLUMN × 5`) | ✅ No existing column is modified or removed |
| No new abstraction layers | ✅ `SRSEngine` is a single struct; `SRSUpdate` is a plain value type |
| `ratingCount` column added to distinguish `new` from `learning` unambiguously | ✅ Simplest correct solution (see Research Decision 6) |

**Gate 5: PASS**

**Constitution Check Result: ALL GATES PASS. Implementation may proceed.**

---

## Project Structure

### Documentation (this feature)

```text
specs/008-srs-engine/
├── plan.md              ← this file
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── srs-engine.md
├── checklists/
│   └── requirements.md
└── tasks.md             ← created by /speckit.tasks (not yet)
```

### Source Code

```text
ClipboardVocab/
├── Models/
│   └── VocabularyEntry.swift          — ADD: srsState, dueDate, interval, easeFactor, ratingCount fields + CodingKeys
├── Services/
│   ├── SRSEngine.swift                — NEW: SRSEngine struct (pure SM-2 function)
│   └── (SRSState.swift, SRSRating.swift, SRSUpdate.swift — new top-level types; may be in SRSEngine.swift or separate files)
├── Persistence/
│   ├── Database.swift                 — ADD: v4 migration (5 new columns + idx_vocabulary_due_date index)
│   └── VocabularyEntryRepository.swift — ADD: fetchDueEntries(), fetchDueCount(), applyRating(id:update:)
│                                          MODIFY: markSaved(id:) to seed SRS defaults
```

**No UI files are modified in this epic.** The Learn and Review views that consume the queue are Epic 4.

**Structure Decision**: `SRSEngine`, `SRSState`, `SRSRating`, and `SRSUpdate` live under `ClipboardVocab/Services/` following the existing service-layer convention. Each type gets its own file if it exceeds ~30 lines; otherwise they may be co-located in `SRSEngine.swift`.

---

## Key Design Decisions (from research.md)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Algorithm | SM-2 with fixed parameters | Well-validated, pure function, no dependencies |
| `interval` type | `REAL` / `Double` | Preserves fractional precision across multiplications |
| `dueDate` type | `TEXT` `YYYY-MM-DD` | Avoids timezone edge cases; lexicographic comparison works for ISO 8601 |
| SRS defaults on save | In `markSaved(id:)` atomically | Prevents inconsistent state window |
| `SRSEngine` boundary | Standalone pure-function struct | Most testable; honours write-failure contract |
| `ratingCount` column | Explicit INTEGER column | Unambiguous `new` vs `learning` distinction |

---

## Complexity Tracking

No constitution violations identified. No complexity justification needed.
