# Research: SRS Engine — Spaced Repetition

**Feature**: 008-srs-engine  
**Date**: 2025-07-22

---

## Decision 1: Algorithm choice — SM-2 vs alternatives

**Decision**: Implement **SM-2** as specified. The algorithm is hardcoded with fixed parameters (`easeFactor` starts at 2.5, minimum 1.3; penalties/bonuses as defined in F-302).

**Rationale**: SM-2 is the original algorithm behind Anki and is extremely well-documented with decades of validated efficacy for vocabulary learning. Its mechanics are simple enough to implement as a pure function with no external dependencies. The parameters in F-302 match the canonical SM-2 spec. Modern alternatives (SM-5, FSRS) offer statistical improvements at the cost of needing more per-card review history and more complex update rules — not justified for a single-user local tool with a relatively small vocabulary set.

**Alternatives considered**:
- **FSRS** (Free Spaced Repetition Scheduler): more accurate for long-term learning; requires tracking review history per card and fitting a forgetting curve model — too complex and no public Swift implementation exists (no new SPM packages, Constitution V).
- **Leitner system**: simpler box-based scheduling; coarser granularity (no continuous ease factor) — would underserve users who have large numbers of cards.
- **Fixed interval doubling**: easy to implement; does not adapt to individual word difficulty — rejected because poor recall (Hard/Again) would still advance the interval.

---

## Decision 2: `interval` storage type — REAL vs INTEGER

**Decision**: Store `interval` as **REAL** (SQLite double-precision float). The Swift field type is `Double`.

**Rationale**: Clarification Q2 established that `interval` accumulates fractional values across ratings (e.g., `2.0 × 2.5 = 5.0`, `5.0 × 2.5 = 12.5`, `12.5 × 2.5 = 31.25`). Storing as REAL preserves these fractional values between sessions — rounding only occurs when computing `dueDate`. Using INTEGER would lose precision and cause compounding rounding errors that distort the schedule over time.

**Alternatives considered**:
- **INTEGER** with round-on-write: simpler schema; but 12.5 days rounded to 13 on write, then multiplied → different schedule than 12.5 × easeFactor. Precision loss compounds over long intervals.
- **TEXT** encoding of a decimal string: avoids float representation issues; far too complex for what is effectively a scheduling number with ≤ 2 significant decimal places.

---

## Decision 3: `dueDate` storage type — TEXT (ISO 8601 date) vs DATETIME

**Decision**: Store `dueDate` as **TEXT** in `YYYY-MM-DD` format (date-only, no time component).

**Rationale**: The spec assumption is "calendar date, no time component, local calendar". SQLite has no native DATE type; GRDB maps `Date` ↔ `DATETIME` which stores seconds-since-epoch — this would encode time-of-day and timezone, creating edge cases when comparing `dueDate ≤ today` near midnight. Storing as a plain `YYYY-MM-DD` string makes the comparison `Column("dueDate") <= todayString` a straightforward lexicographic string comparison (which works correctly for ISO 8601 dates). The Swift side uses `String` for this column and converts to/from `Calendar.current` when needed.

**Alternatives considered**:
- **DATETIME (Double/epoch)**: stores full timestamp; requires stripping time-of-day before comparison; timezone-sensitive — rejected because it introduces exactly the edge cases the assumption wanted to avoid.
- **INTEGER (Julian day)**: compact; but GRDB has no built-in Julian day support; manual conversion required — added complexity for no benefit.

---

## Decision 4: Where to apply SRS defaults on Inbox save — repository vs service layer

**Decision**: Apply SRS default values (`srsState = 'new'`, `dueDate = today`, `interval = 1.0`, `easeFactor = 2.5`) **in the repository's `markSaved(id:)` method** (from Epic 2), not in a separate service call.

**Rationale**: When the user taps Save in the Inbox, `markSaved(id:)` already writes a single UPDATE to the DB. Extending that UPDATE to also set the four SRS columns keeps the transition atomic — there is no window where `triageStatus = 'saved'` but SRS fields are unset. Doing it in a separate post-save call would require two transactions and create a brief inconsistent state visible to the `ValueObservation`.

**Alternatives considered**:
- **Set defaults at INSERT time** (in `upsert`): rejected — at insert time the entry is `unreviewed`, not yet in the learning pipeline. Setting SRS fields to "due today" for entries the user hasn't even decided to keep is misleading and pollutes the daily queue with unsaved words.
- **Separate `SRSService.initialise(entry:)` call after save**: rejected — two-phase write without a transaction; if the second call fails, the entry is `saved` but has no SRS state, corrupting the queue.

---

## Decision 5: `SRSEngine` pure function boundary — standalone type vs extension on `VocabularyEntry`

**Decision**: Implement `SRSEngine` as a **standalone value type (struct)** with a single static (or instance) method: `func rate(_ entry: VocabularyEntry, rating: SRSRating) -> SRSUpdate` where `SRSUpdate` is a small value type carrying the four updated fields.

**Rationale**: A pure function with no stored state is the most testable form. Returning a dedicated `SRSUpdate` value (rather than a mutated copy of the full entry) keeps the engine decoupled from the full `VocabularyEntry` model — the engine only needs to know `interval` and `easeFactor`, not translation text or capture timestamps. This also avoids mutating the entry in memory before the write succeeds (required by the write-failure contract).

**Alternatives considered**:
- **Extension on `VocabularyEntry`** with a mutating `rate(_:)` method: rejected — mutating the model before persistence succeeds violates the write-failure contract (F-304: entry's SRS fields must not be mutated until the write succeeds).
- **Protocol-based `SRSAlgorithm`** with a concrete implementation: over-engineering for a single fixed algorithm (Constitution V); no alternative algorithm is planned.

---

## Decision 6: Rating count tracking — explicit `ratingCount` column vs derived from state

**Decision**: Add a **`ratingCount` column** (`INTEGER NOT NULL DEFAULT 0`) to track the number of ratings submitted for an entry. This is used to distinguish `new` (0 ratings) from `learning` (≥ 1 rating, interval < 7).

**Rationale**: The `new` vs `learning` distinction (Clarification Q1) is defined by whether the entry has ever been rated — this is a distinct piece of information from `interval`. Without `ratingCount`, the only way to detect "never rated" is to check `interval == 1.0 AND srsState == 'new'`, which is ambiguous (an `Again` rating also resets interval to 1.0). Storing an explicit count eliminates ambiguity, costs one integer column, and enables future stats use (Epic 5 could surface "cards never attempted").

**Alternatives considered**:
- **Infer from `srsState`**: `srsState == 'new'` implies 0 ratings; but after an `Again` rating the state reverts to `learning`, not `new` — so state alone cannot distinguish "never rated" from "rated and reset".
- **Separate review history table**: accurate but far over-engineered for this purpose (Constitution V).
