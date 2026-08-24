# Research: Inbox Word Management & Learn Session Control

**Feature**: 010-inbox-word-management  
**Date**: 2025-07-25

---

## Decision 1: How to represent "mastered" — new column vs repurposing `srsState`

**Decision**: Add a **`isMastered: Bool`** column (migration `v6`) to `vocabulary_entries`, defaulting to `false`. The mastery flag is set in an atomic write alongside the `applyRating` call when the rating is `.easy`. `fetchDueEntries()` gains an additional filter `isMastered == false`.

**Rationale**: `srsState` already has a `.mastered` case derived from `interval ≥ 21` — but this is an _algorithmic_ state driven by the SRS formula, not a _user decision_. A user can rate a card Easy with a short interval (first session), which would not produce `srsState = .mastered` via the formula. The spec requirement is explicit: "rating Easy = mastered". Overloading `srsState.mastered` for this purpose would corrupt the SM-2 algorithm's state derivation logic and conflict with existing tests. A dedicated boolean column keeps the two concepts cleanly separated: `srsState` belongs to the algorithm; `isMastered` belongs to the user's explicit decision.

**Alternatives considered**:
- **Reuse `srsState = .mastered`**: breaks the SM-2 derivation rule (interval threshold vs user tap). Would require patching `SRSEngine.deriveState` to never return `.mastered` for the algorithm, which is inconsistent.
- **Store a `masteredDate: String?` column**: more expressive (allows future Stats queries on "when was this word mastered") but overkill for this feature's requirements. Can be added in a future Epic 5 migration; `isMastered` is sufficient now.

---

## Decision 2: Mastery write — atomic with `applyRating` or separate call

**Decision**: Set `isMastered = true` in a **separate, targeted UPDATE** (`markMastered(id:)` repository method), called from the view action handler after `applyRating` succeeds for an `.easy` rating.

**Rationale**: `applyRating` is an Epic 3 contract that "does NOT touch `triageStatus`, `englishText`, `frenchTranslation`, or any other column" (contract C-32/C-34). Extending it to also set `isMastered` would violate the Epic 3 contract and conflate SRS scheduling with mastery state. The two writes can be issued sequentially in the same `Task` — if `markMastered` fails after `applyRating` succeeds, the word has its SRS fields updated but `isMastered` remains `false`. In practice this means it will still appear in future queues until the flag is set. This is acceptable because: (a) local SQLite writes rarely fail independently, and (b) the word will be presented again with a long interval, giving the user the opportunity to rate Easy again.

**Alternatives considered**:
- **Single compound UPDATE in a new `applyRatingAndMaster(id:update:)` method**: achieves atomicity but violates the clean separation between SRS scheduling and mastery state. Also requires special-casing `.easy` inside the repository layer, which knows nothing about rating semantics.
- **Extend `SRSUpdate` with an `isMastered: Bool` field**: same problem — couples the SRS scheduling struct to mastery logic.

---

## Decision 3: Multi-select state — in-view `@State` vs external view model

**Decision**: Inbox selection state (`isSelecting: Bool`, `selectedIDs: Set<Int64>`) lives in **`@State` directly on the Inbox view** (or a view modifier). No external view model is introduced.

**Rationale**: Selection mode is entirely transient UI state — it is not persisted, not shared across views, and produces no asynchronous output until the user taps Delete or Add to Learn. Keeping it as local `@State` is consistent with the project's existing approach (the `FocusSession` is also local `@State` per Research Decision 3 in Epic 4). The Constitution (Principle V) warns against new architectural layers without justification. A separate `@StateObject` / `ObservableObject` view model would be over-engineering for two boolean / set fields.

**Alternatives considered**:
- **`@StateObject` with a selection manager class**: unnecessary overhead; no async work occurs during selection; there are no subscribers.
- **Pass selection state to `VocabularyEntryRepository`**: selection is UI-only — the repository layer must remain ignorant of it.

---

## Decision 4: Bulk delete — individual calls vs batch SQL

**Decision**: Issue a **single batch DELETE** using GRDB's `VocabularyEntry.deleteAll(_:keys:)` or equivalent multi-row DELETE for all selected IDs in a single `dbQueue.write`.

**Rationale**: Issuing N individual `delete(id:)` calls inside separate `dbQueue.write` blocks is valid but generates N separate write transactions and N `ValueObservation` fires. A single transaction is more efficient and produces exactly one observation update. GRDB supports batch deletes via `VocabularyEntry.filter(keys: ids).deleteAll(db)`.

**Alternatives considered**:
- **Sequential individual deletes**: works but generates multiple ValueObservation fires, causing the list to animate N times. Acceptable for small N but perceptually worse.
- **Raw SQL `DELETE WHERE id IN (...)`**: equivalent to the GRDB API approach; use the GRDB API for consistency with existing code.

---

## Decision 5: On-demand Learn session (Inbox → Learn) — replace or queue alongside SRS session

**Decision**: An on-demand session **replaces any paused Focus Session**. The spec is explicit: the `@State var session: FocusSession?` on `VocabularySidebarView` is simply overwritten with a new `FocusSession` constructed from the promoted entries. No separate "on-demand session" type is needed — `FocusSession` already supports arbitrary entry arrays.

**Rationale**: `FocusSession` is agnostic about where its entries came from. Constructing one with the promoted entries and assigning it to the binding is identical to starting a regular SRS session. The view already navigates to the Learn tab after the assignment. This requires zero new types and zero changes to `FocusSession` — only a new initialisation path in the view.

**How session origin is communicated**: `FocusSession` gains an `isOnDemand: Bool` flag that distinguishes sessions constructed from Inbox promotions vs the SRS queue. This flag controls the Restart behaviour: an on-demand session's Restart draws from the same on-demand pool (the originally promoted entries + any SRS-eligible entries, per spec FR-010 which says Restart uses the full available pool).

**Alternatives considered**:
- **Separate `OnDemandSession` type**: no benefit over a flag; adds unnecessary type complexity.
- **Allow both an SRS session and an on-demand session to coexist**: contradicts the spec ("Add to Learn replaces any paused session").

---

## Decision 6: Restart session — pool definition and random sampling

**Decision**: The "Learn-eligible pool" for Restart is **all `VocabularyEntry` rows where `triageStatus = 'saved'` AND `isMastered = false`** — not just the SRS daily queue. This is a broader pool: it includes entries with future `dueDate` values as well as today's due entries.

**Rationale**: The spec defines the pool as "all non-mastered vocabulary entries that have been saved" (Assumptions section). The SRS daily queue (`dueDate ≤ today`) is a subset of this. For a Restart session, the user wants to practice from all saved words, not only today's overdue ones. This is the natural expectation for a manual restart.

**Random sampling**: When pool size > 20, use `Array.shuffled()` then take the first 20 elements. `Array.shuffled()` uses Swift's `SystemRandomNumberGenerator` — no seed, no import needed.

**Alternatives considered**:
- **Restart using only today's SRS queue**: too narrow; if the user already rated everything, the pool would be empty even though they have 100 saved words.
- **Custom `SeededRandomNumberGenerator`**: not needed; reproducibility is not a requirement. System random is simpler and matches the spec ("system random").

---

## Decision 7: `markMastered` — repository method scope

**Decision**: Add **`func markMastered(id: Int64) throws`** to `VocabularyEntryRepository`. It issues a single UPDATE: `SET isMastered = true WHERE id = ?`.

**Rationale**: This follows the exact pattern of `markSaved`, `markIgnored`, `markKnown`, and `setDifficultyLabel` — each is a targeted single-column (or small group) UPDATE. Adding a new method keeps the repository interface explicit and each method's column contract clear. The method is `throws`; callers use `try repository.markMastered(id:)` inside a `Task` (the write can fail; it must be caught, not silently swallowed, because mastery is a significant state change).

**Alternatives considered**:
- **Extend `applyRating` to accept an `isMastered` flag**: violates the SRS separation described in Decision 2.
- **General `update(entry:)` with a mutated entry**: loads the full row, mutates it, writes all columns. Wasteful and risks overwriting concurrent changes to other fields.

---

## Decision 8: `fetchLearnPool()` — new repository query

**Decision**: Add **`func fetchLearnPool() throws -> [VocabularyEntry]`** to `VocabularyEntryRepository`. It returns all entries where `triageStatus = 'saved'` AND `isMastered = false`, ordered by `dueDate` ascending (overdue-first, consistent with the SRS queue ordering).

**Rationale**: Both `startSession()` (Restart) and the `ValueObservation` that drives the idle-state word count need this query. Centralising it in the repository avoids inline filter logic in the view and makes the query testable. The ordering matches the SRS queue for consistency — the user sees overdue words first even in a restarted session.

**Alternatives considered**:
- **Compute in the view by filtering `fetchAll()`**: requires loading all entries (including ignored/unreviewed) and filtering in Swift. Wasteful and untestable.
- **Extend `fetchDueEntries()` to accept a `mastered` flag**: the daily queue (dueDate ≤ today) is a different query from the full learn pool. Keep them separate to preserve Epic 3's contract.
