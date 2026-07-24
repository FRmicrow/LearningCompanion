# Research: Vocabulary Panel UI

**Branch**: `002-vocabulary-panel-ui` | **Date**: 2025-07-22
**Source**: Codebase analysis of `ClipboardVocab/` + existing `specs/001-clipboard-vocab-capture/` artifacts

---

## Decision 1: Schema extension — `isRetained` column

**Decision**: Add an `isRetained INTEGER NOT NULL DEFAULT 0` column to the `vocabulary_entries` table via a GRDB v2 migration, mapping to `Bool` in Swift through GRDB's built-in `Bool` ↔ `INTEGER` codec.

**Rationale**: The retained state must survive app restarts (FR-006, SC-005). SQLite is the existing persistence layer; adding a column is the minimal, zero-dependency change. `DEFAULT 0` means all existing entries start as unretained after the migration, which is the correct semantic.

**Alternatives considered**:
- Separate `retained_entries` join table: Adds unnecessary complexity; retained state is a property of a single entry, not a relationship.
- In-memory `@AppStorage` / UserDefaults keyed by entry ID: Does not survive entry deletion and re-insertion; not suitable for per-row state.

---

## Decision 2: Date-grouping strategy — computed in Swift, not SQL

**Decision**: Fetch all entries via `ValueObservation` (as today), then group by calendar day of `firstCapturedAt` using `Calendar.current.dateComponents([.year, .month, .day], from:)` in a computed property on the view model / view.

**Rationale**: The existing `VocabularyListView` already uses a `ValueObservation` that fetches all rows. Grouping in Swift avoids adding a SQL `GROUP BY` query while keeping a single reactive observation. Entry count per user is in the tens-to-hundreds range — Swift grouping is negligible overhead.

**Alternatives considered**:
- SQL `GROUP BY DATE(firstCapturedAt)`: Would require a second query or a raw SQL observation; harder to compose with GRDB's typed `ValueObservation` API.
- `Section` with `ForEach` over a `Dictionary(grouping:)`: Chosen. Swift standard library `Dictionary(grouping:by:)` is idiomatic and produces the required `[String: [VocabularyEntry]]` structure with a single pass.

---

## Decision 3: "Old unretained" threshold — 7-day computed filter, no DB index

**Decision**: Compute `Date().addingTimeInterval(-7 * 24 * 3600)` at observation time and filter in Swift: `entries.filter { !$0.isRetained && $0.firstCapturedAt < cutoff }`.

**Rationale**: The feature is read-only display derived from the same `ValueObservation` used for the main list. No additional DB query needed. At hundreds of entries the filter is O(n) and imperceptible.

**Alternatives considered**:
- Separate GRDB query with `WHERE firstCapturedAt < ? AND isRetained = 0`: Feasible but adds a second observation; the single-observation approach keeps the reactive graph simple.
- Index on `(firstCapturedAt, isRetained)`: Premature optimisation for the expected data volume.

---

## Decision 4: "Retry Translation" — per-date-group action, reuses existing `TranslationService`

**Decision**: Add a `retryGroup(entries: [VocabularyEntry]) async` method to `TranslationService` that iterates the passed entries and calls the existing `translate(entry:)` on each. The `VocabularyDateGroupSection` view calls this via a `Task` on button tap.

**Rationale**: `TranslationService.translate(entry:)` already handles individual retry and DB write. Grouping is purely a UI concern — the service doesn't need to know about date groups. Reusing the existing method avoids duplicating the retry logic.

**Alternatives considered**:
- A new `retryGroup` that only retranslates `.pending` entries in the group: The spec (FR-008, scenario 2) states the button should refresh all entries in the group even if already translated, so we pass all entries (the service will overwrite with a fresh translation).
- Exposing a group-level queue on `TranslationService`: Over-engineered for the current scope.

---

## Decision 5: Checkbox "ok" — `Toggle` with `isRetained` binding, immediate DB write

**Decision**: `VocabularyEntryRow` receives an `isRetained: Bool` binding. Toggling calls `repository.markRetained(id:_:)` on a `Task`. GRDB `ValueObservation` propagates the DB change back to `@State var entries`, closing the reactive loop.

**Rationale**: Consistent with the existing `onDelete` / `onRetry` callback pattern in `VocabularyEntryRow`. The `Toggle` maps directly to the boolean and requires no local state.

**Alternatives considered**:
- Optimistic local `@State` update before DB write: Would complicate the conflict-resolution logic if the DB write fails; unnecessary for this feature since writes are fast local SQLite ops.

---

## Decision 6: Panel layout — retain `NSPopover` / `NSHostingController`, widen frame

**Decision**: Keep `StatusItemController`'s existing `NSPopover` + `NSHostingController(rootView: VocabularyListView(...))` stack. Widen the frame from 320 pt to ~380 pt and increase `maxHeight` to accommodate date headings and the old-words section.

**Rationale**: The spec says "panel affiché à gauche de l'écran" — in the macOS menu-bar app context this means the popover appears to the left of / below the status item, which is already the behaviour of the existing popover (`.preferredEdge = .minY`). A full `NSPanel`/`NSWindow` sidebar would require switching to a regular app with a Dock icon, which is a larger architectural change not requested.

**Alternatives considered**:
- Full `NSWindow` sidebar docked to left of screen: Requires `NSApplicationActivationPolicyRegular` and a main window, fundamentally changing the app model. Out of scope.
- `NavigationSplitView` within the popover: Adds hierarchy where none is needed; the list is flat within each date group.

---

## NEEDS CLARIFICATION — resolved

All technical unknowns were resolvable from the codebase without user input. No open clarifications remain.
