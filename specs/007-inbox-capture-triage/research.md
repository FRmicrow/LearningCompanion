# Research: Inbox — Capture & Triage

**Feature**: 007-inbox-capture-triage  
**Date**: 2025-07-21

---

## Decision 1: Triage state representation — new column vs new table vs repurposing existing fields

**Decision**: Add a `triageStatus` column (`TEXT NOT NULL DEFAULT 'unreviewed'`) to the existing `vocabulary_entries` table via an additive migration (`v3`). Values: `unreviewed` · `saved` · `ignored` · `known`.

**Rationale**: The Inbox is a view into existing vocabulary entries filtered by their triage state — it is not a separate concept. Adding a column to the existing table keeps the schema flat and avoids a join. The three existing fields that might be repurposed (`isRetained`, `translationStatus`) carry different semantics (`isRetained` = user's long-term keep/delete flag from the old UI; `translationStatus` = translation pipeline state) and must not be overloaded. GRDB migrations are forward-only and additive changes are the project's preferred pattern (Constitution V).

**Alternatives considered**:
- Repurpose `isRetained = true` as "saved" — rejected because `isRetained` means "user has kept this word long-term", which is a different concept from "user has triaged this word into the vocab list". Overloading would break the old UI sections (`OldUnretainedWordsSection`) still in the codebase.
- Separate `inbox_items` join table — rejected as over-engineering for a single-user tool with < 50 Inbox items (Constitution V).
- In-memory filter (no schema change) — rejected because triage decisions must survive app restarts; a word dismissed from the Inbox must stay dismissed.

---

## Decision 2: How new captures enter the Inbox — default value of `triageStatus`

**Decision**: The `triageStatus` column defaults to `'unreviewed'` in SQL. `VocabularyEntryRepository.upsert(englishText:)` sets no explicit value — the SQL default applies automatically. No change to the existing upsert method is required.

**Rationale**: The upsert method is called by `CaptureProcessorService` on every successful clipboard capture. By defaulting to `'unreviewed'`, every newly inserted row automatically appears in the Inbox without any code change to the capture pipeline. Deduplication (FR-011) is already handled by the `UNIQUE` constraint on `englishText` + the upsert logic — a re-captured word's `triageStatus` stays as-is (no downgrade from `saved` back to `unreviewed`).

**Alternatives considered**:
- Modify `CaptureProcessorService` to set `triageStatus = .unreviewed` explicitly — rejected as unnecessary because the SQL default covers it and touching the capture pipeline risks regression.
- Reset `triageStatus` to `unreviewed` on re-capture — rejected because if the user has already saved/ignored a word and then copies it again, resetting would undo their triage decision. Existing `seenCount` increment already records the re-capture.

---

## Decision 3: SwiftUI swipe gestures — `.swipeActions` vs custom gesture recogniser

**Decision**: Use SwiftUI's native `.swipeActions(edge:)` modifier on `List` row items (available since macOS 13).

**Rationale**: SwiftUI `.swipeActions` is the idiomatic, zero-dependency approach for list-row swipes on macOS 13+. It matches Mail.app's interaction model exactly (left swipe → Delete destructive red button; right swipe → Known green button). No custom `NSGestureRecognizer` or third-party package is required, satisfying Constitution V (no new dependencies). The 300 ms SC-004 target is achievable because `.swipeActions` uses native AppKit list row animation.

**Alternatives considered**:
- Custom `DragGesture` with threshold detection — rejected because it requires manual animation, hit-testing, and reset logic, adding significant complexity for no user-facing benefit.
- `NSTableView`-based swipe (`NSTableViewRowAction`) — rejected because the UI layer is SwiftUI; going to AppKit just for swipe gestures would require a custom `NSViewRepresentable` wrapper, violating Constitution V's simplicity principle.

---

## Decision 4: Menu-bar badge — `NSStatusItem` badge vs custom image composition

**Decision**: Drive the badge by observing the `unreviewed` Inbox count via a dedicated `ValueObservation` in `StatusItemController`. When count > 0, compose a badge image programmatically by drawing on top of the base SF Symbol icon using `NSImage`/`NSBitmapImageRep`. When count = 0, restore the base icon.

**Rationale**: `NSStatusItem` has no native badge API (unlike `NSDockTile`). The correct macOS pattern is to redraw the menu-bar button image with an overlaid count badge. The composition must run on the main thread. Driving it from a `ValueObservation` means the badge reacts to every DB write — the same mechanism already used for all live UI updates (Constitution IV). This approach requires no new dependency.

**Alternatives considered**:
- `NSDockTile.badgeLabel` — rejected because the app is `LSUIElement = YES` (no Dock icon).
- Notification-based badge update — rejected because `NotificationCenter` is explicitly prohibited for live UI updates (Constitution IV requires `ValueObservation` as the exclusive mechanism).
- Third-party menu-bar badge library — rejected (Constitution V).

---

## Decision 5: Inbox entry focus model — focused single-card vs scrollable list

**Decision**: Display the Inbox as a **scrollable list** of `InboxEntryCard` rows (same pattern as the existing `VocabularyListView`). Each card shows the word, a collapsed translation slot, and per-row action buttons. There is no single "focused card" that fills the entire view.

**Rationale**: The spec shows a list pattern (multiple words queued; swipe gestures on list items — FR-006, FR-007). A single-card focus mode (Anki-style one-at-a-time) is described for the **Learn** tab in Epic 4, not the Inbox. For triage, scanning a list is faster — the user may want to save several words in sequence. This also keeps the Inbox consistent with the existing `VocabularyListView` the user is already familiar with.

**Alternatives considered**:
- Single-card focus mode — deferred to Epic 4 (Learn tab). Considered for Inbox but rejected because the backlog spec explicitly lists it under "Learn" mode, not "Inbox".
- The `InboxEntryCard` shows the translation as hidden by default with an inline Reveal button, matching FR-002 and FR-003 without needing a full-screen card approach.

---

## Decision 6: Translation reveal state — per-entry vs global

**Decision**: Each `InboxEntryCard` manages its own `@State var isRevealed: Bool = false` locally. Pressing Reveal on card A does not reveal translation on card B.

**Rationale**: Each word is an independent triage decision. Revealing one translation should not affect other cards. Storing reveal state per-card in `@State` (local to the SwiftUI view) is the simplest model — it resets naturally when the entry is removed from the list. A global `Set<Int64>` of revealed IDs in the parent `InboxView` is unnecessary complexity.

**Alternatives considered**:
- Global revealed IDs in `InboxView` — rejected because on swipe-to-delete or Save, the ID is removed from the list; cleaning up the Set adds maintenance overhead with no benefit.
- Reveal state persisted to DB — rejected because reveal state is purely ephemeral session state (the user sees it once while deciding; once saved/ignored the card disappears).

---

## Decision 7: `Space` key reveal — scope in the list context

**Decision**: The `Space` key (FR-003) reveals the translation of the **topmost** (first) unreviewed entry in the list. It uses the same `InboxKeyboardShortcutsModifier` pattern already established in `VocabularyListView` — a hidden `Button` with `.keyboardShortcut(.space, modifiers: [])` on macOS 14+ via `.onKeyPress`.

**Rationale**: In a list context there is no concept of "focused row" that Space naturally maps to. Defaulting to the first/top item is the least surprising behaviour — it allows the user to quickly triage by keyboard: press Space (reveal), press Enter (save), repeat. This matches the backlog's intended keyboard-driven flow. The existing `InboxKeyboardShortcutsModifier` in `VocabularyListView` already implements this pattern and will be adapted for `InboxView`.

**Alternatives considered**:
- Space reveals the currently focused/selected row — rejected because `List` focus on macOS is keyboard-cursor-based and selecting a row via keyboard is a different gesture; mixing the two would be confusing.
- Per-card Space via `.focusable()` — rejected as too complex for this epic; deferred to Epic 6 polish.
