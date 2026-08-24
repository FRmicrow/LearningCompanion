# Research: Learn & Review — Sessions de révision

**Feature**: 009-learn-review-sessions  
**Date**: 2025-07-23

---

## Decision 1: `FocusSession` state representation — value type vs reference type

**Decision**: Implement `FocusSession` as a **value type (struct)** held in `@State` inside the Learn/Review tab view.

**Rationale**: The session state (card list captured at start, current index, rated count, per-rating tally) is simple, non-recursive, and has no shared-mutation requirements. A struct held in `@State` gives SwiftUI automatic change detection and zero retain-cycle risk. The session is paused (preserved in memory) by keeping the `@State` variable alive in the parent tab container while the tab is off-screen — this is the natural SwiftUI model. The spec's clarification that "session state is preserved in memory for the lifetime of the app session" maps exactly to `@State` on the parent container view that is never deallocated while the sidebar is open.

**Alternatives considered**:
- **`@StateObject` with a class (`ObservableObject`)**: appropriate when state has async tasks or subscribers. `FocusSession` is a snapshot — no async work happens inside the session value itself; the async work (rating writes) is dispatched outside it. Using a class would add unnecessary `objectWillChange` overhead.
- **`@EnvironmentObject`**: ruled out — the session is local to the Learn/Review tab container; injecting it into the environment would pollute the whole view hierarchy and create invisible dependencies.

---

## Decision 2: How to gate rating keyboard shortcuts before Reveal

**Decision**: Use a **`@State var isRevealed: Bool`** flag on the card view. The keyboard shortcut handlers for `1`/`2`/`3`/`4` are guarded by `guard isRevealed else { return }`. The Space shortcut sets `isRevealed = true` and has no guard.

**Rationale**: This is the simplest correct implementation. SwiftUI `.keyboardShortcut` modifiers are attached to `Button` views. Making the rating buttons conditionally visible (shown only after reveal) is sufficient to prevent accidental activation by click. For keyboard paths, a guard on the handler is the standard SwiftUI pattern — it requires zero additional state and is trivially testable (flip the flag, assert the guard fires).

**Alternatives considered**:
- **Disable buttons via `.disabled(!isRevealed)`**: visually disables them but they remain in the view hierarchy and `.disabled` does not prevent keyboard shortcut activation in all SwiftUI versions. A guard in the action closure is more reliable.
- **Conditional rendering (`if isRevealed`)**: removes the buttons entirely until revealed. Correct and acceptable, but causes layout shift when the buttons appear. The spec's design intent (rating buttons "appear" after reveal) favours this approach for the *visual* layer — the guard approach works for the keyboard layer. In practice: render rating buttons only after `isRevealed = true` (handles both visual and keyboard paths cleanly).

**Resolved**: Render rating buttons only after `isRevealed = true`. This satisfies both the visual spec and the keyboard guard requirement without any extra logic.

---

## Decision 3: Session pause/resume — where to hold the `FocusSession` state

**Decision**: The `FocusSession` struct is stored in `@State` on the **tab container view** (the view that owns the Learn and Review tab switcher, equivalent to the `NavigationStack` or `TabView` body in the sidebar). It is passed down to `LearnView` and `ReviewView` via a binding.

**Rationale**: The clarification establishes that session state must survive tab switches. In SwiftUI, `@State` on a parent view persists as long as the parent view is alive — which is the lifetime of the sidebar panel. Navigating to the Inbox or Stats tab does not deallocate the sidebar container; it merely hides the Learn/Review content. Storing the session on the container (not on `LearnView` or `ReviewView` directly) means the state is never reset when the child view disappears and reappears.

**Alternatives considered**:
- **Store in `AppDelegate` or a singleton**: unnecessarily broad scope; the session is not needed outside the sidebar.
- **`@StateObject` with a shared view model on the container**: equivalent outcome but heavier. A plain struct in `@State` is sufficient since no external subscriptions are needed on `FocusSession` itself.

---

## Decision 4: `difficultyLabel` write — async fire-and-forget vs `Task { try }` with error handling

**Decision**: The immediate `difficultyLabel` write is dispatched as **`Task { try? repository.setDifficultyLabel(id:label:) }`** (fire-and-forget with silent failure).

**Rationale**: `difficultyLabel` is explicitly specified as a user annotation with no impact on the SRS algorithm. A write failure means the label is not persisted — on the next session the selector simply shows blank again. This is a minor UX degradation, not a data-integrity issue. Surfacing an error indicator for a difficulty tap (which takes 50 ms to write) would be jarring and disproportionate. The spec does not require error handling for this write path, and the project rules note that error handling for scenarios that "cannot happen" under normal conditions should not be added.

**Alternatives considered**:
- **`Task { try repository.setDifficultyLabel(...) }` with an error catch that surfaces a toast**: the spec does not require this; adds code for a near-impossible failure mode on a local SQLite write.
- **Inline synchronous write (blocking the main thread)**: never acceptable in a SwiftUI view action handler.

---

## Decision 5: `SessionRatingTally` — inline fields vs dedicated value type

**Decision**: Introduce a small **`SessionRatingTally` struct** with four `Int` fields (`again`, `hard`, `good`, `easy`) as a nested type inside `FocusSession`.

**Rationale**: The completion screen must display per-rating counts (Clarification Q5). These four counts need to travel with the `FocusSession` value so that when the session completes, the `SessionCompletionView` receives them without an additional query. Embedding them as a dedicated nested struct (`FocusSession.RatingTally`) is cleaner than four separate fields on `FocusSession` and is trivially composable. The struct is never persisted — it lives only in memory for the session lifetime.

**Alternatives considered**:
- **Four separate `Int` properties on `FocusSession`**: functionally equivalent but less cohesive; the tally is logically a single unit.
- **A dictionary `[SRSRating: Int]`**: works but requires explicit `SRSRating` cases as keys; accessing individual counts is more verbose. The struct is simpler.

---

## Decision 6: `lastReviewedDate` update — inside `applyRating` vs separate write

**Decision**: `lastReviewedDate` is updated **inside the existing `applyRating(id:update:)` call** — the `SRSUpdate` struct from Epic 3 is extended with a `lastReviewedDate: String` field (or the repository method adds it as an additional parameter).

**Rationale**: The spec states `lastReviewedDate` is set on every successful rating write. The most atomic approach is to include it in the same `UPDATE` statement as the SRS fields (F-304's single transaction). Doing a separate write would create a two-phase commit for what is logically one event. Since `applyRating` already owns the rating write transaction, extending it to also write `lastReviewedDate` in the same `UPDATE` is minimal, safe, and consistent with the project's established "atomic update" pattern (see Research Decision 4 in Epic 3).

**Approach**: Add `lastReviewedDate: String` to `SRSUpdate` and include it in the `SET` clause of `applyRating`'s UPDATE statement.

**Alternatives considered**:
- **Separate `updateLastReviewed(id:)` call after `applyRating`**: two writes; if the second fails, `dueDate` is updated but `lastReviewedDate` is stale. Violates atomicity.
- **Computed property derived from rating history**: would require a review history table (over-engineering; ruled out in Epic 3 Research Decision 6).

---

## Decision 7: New repository method for `difficultyLabel`

**Decision**: Add **`setDifficultyLabel(id: Int64, label: DifficultyLabel) throws`** to `VocabularyEntryRepository`. It issues a single `UPDATE` touching only `difficultyLabel`.

**Rationale**: The difficulty write is independent of the SRS rating write (Clarification Q2). A dedicated method keeps concerns separated and the UPDATE minimal. It follows the existing project pattern for single-field updates (e.g., `markSaved` updates `triageStatus` and SRS fields; `applyRating` updates SRS fields — each method owns its columns).

**Alternatives considered**:
- **Extend `applyRating` with an optional `difficultyLabel` parameter**: muddles the SRS concern with the annotation concern. The difficulty can be written before, after, or without a rating — coupling them in one method creates awkward optional parameters.
