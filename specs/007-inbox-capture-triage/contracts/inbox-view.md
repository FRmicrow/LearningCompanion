# Contract: Inbox View

**Feature**: 007-inbox-capture-triage  
**Date**: 2025-07-21  
**Type**: UI Contract (SwiftUI view layer) + Repository extension

---

## Overview

This contract defines:

1. **`InboxView`** — the SwiftUI view that populates the `.inbox` tab inside `VocabularySidebarView`.
2. **`InboxEntryCard`** — the per-row card component rendered inside `InboxView`.
3. **New `VocabularyEntryRepository` methods** — `fetchInbox()`, `fetchInboxCount()`, `markSaved(id:)`, `markIgnored(id:)`, `markKnown(id:)`.
4. **`StatusItemController` badge extension** — `startBadgeObservation(repository:)` and `updateBadge(count:)`.
5. **`VocabularyEntry.TriageStatus`** — the new enum type.
6. **`VocabularySidebarView` integration** — replacement of `VocabularyListView` with `InboxView` in the `.inbox` tab case.

---

## `VocabularyEntry.TriageStatus`

```swift
extension VocabularyEntry {
    enum TriageStatus: String, Codable {
        case unreviewed = "unreviewed"
        case saved      = "saved"
        case ignored    = "ignored"
        case known      = "known"
    }
}
```

| # | Contract |
|---|----------|
| C-01 | `VocabularyEntry` gains a `triageStatus: TriageStatus` stored field. |
| C-02 | `TriageStatus` raw values match the SQL column values defined in migration `v3`. |
| C-03 | `VocabularyEntry.CodingKeys` is extended with `triageStatus = "triageStatus"` (camelCase → camelCase per project convention). |
| C-04 | Migration `v3` adds `ALTER TABLE vocabulary_entries ADD COLUMN triageStatus TEXT NOT NULL DEFAULT 'unreviewed'` followed by `CREATE INDEX idx_vocabulary_triage_status ON vocabulary_entries (triageStatus)`. |
| C-05 | `upsert(englishText:)` is **not modified**. New rows receive `triageStatus = 'unreviewed'` via the SQL column default. |

---

## `VocabularyEntryRepository` — New Methods

```swift
/// Returns all entries with triageStatus == .unreviewed, newest-first.
func fetchInbox() throws -> [VocabularyEntry]

/// Returns the count of entries with triageStatus == .unreviewed.
func fetchInboxCount() throws -> Int

/// Sets triageStatus = .saved for the given entry id.
func markSaved(id: Int64) throws

/// Sets triageStatus = .ignored for the given entry id.
func markIgnored(id: Int64) throws

/// Sets triageStatus = .known for the given entry id.
func markKnown(id: Int64) throws
```

| # | Contract |
|---|----------|
| C-06 | All five methods are synchronous `throws` functions. Callers wrap them in `Task { try? ... }` on the main thread. |
| C-07 | `fetchInbox()` filters `Column("triageStatus") == TriageStatus.unreviewed.rawValue` and orders by `Column("firstCapturedAt").desc`. |
| C-08 | `fetchInboxCount()` uses GRDB `fetchCount(db)` on the same filter predicate as `fetchInbox()`. |
| C-09 | `markSaved`, `markIgnored`, `markKnown` execute `UPDATE vocabulary_entries SET triageStatus = ? WHERE id = ?` with the appropriate raw value. |
| C-10 | None of the new methods touch `isRetained`, `translationStatus`, or any other column. |
| C-11 | GRDB `ValueObservation` fires automatically after write operations — no explicit notification is needed. |

---

## `InboxView`

### Responsibility

Populates the `.inbox` tab. Observes the list of unreviewed entries via `ValueObservation`. Handles triage actions. Forwards badge count updates to `StatusItemController` via a callback closure.

### Interface

```swift
struct InboxView: View {
    let repository: VocabularyEntryRepository
    let translationService: TranslationService
}
```

### Behavioural Contracts

| # | Contract |
|---|----------|
| C-12 | `InboxView` renders a `List` of `InboxEntryCard` rows, one per `unreviewed` entry. |
| C-13 | Entries are ordered newest-first (driven by `fetchInbox()` order). |
| C-14 | When the entry list is empty, `InboxView` renders `InboxEmptyStateView` (a new empty-state specific to the Inbox). |
| C-15 | `InboxView` starts a `ValueObservation` on `.onAppear` and cancels it on `.onDisappear`, following the existing pattern in `VocabularyListView`. The task is stored in `@State private var observationTask: Task<Void, Never>?`. |
| C-16 | The `ValueObservation` filters on `triageStatus == 'unreviewed'` (not all entries). |
| C-17 | Triage actions (`save`, `ignore`, `known`) call the corresponding repository method inside `Task { try? ... }`. The `ValueObservation` fires automatically and refreshes the list. |
| C-18 | `InboxView` applies `InboxKeyboardShortcutsModifier` (adapted from `VocabularyListView`) with: Space → reveal top entry, ⌘H → toggle top entry translation, Enter → save top entry. |

---

## `InboxEntryCard`

### Responsibility

A single row card displaying one unreviewed vocabulary entry. Manages its own `isRevealed` state.

### Interface

```swift
struct InboxEntryCard: View {
    let entry: VocabularyEntry
    let onSave: () -> Void
    let onIgnore: () -> Void
    let onKnown: () -> Void
}
```

### Behavioural Contracts

| # | Contract |
|---|----------|
| C-19 | The card displays `entry.englishText` prominently (headline font). |
| C-20 | The translation area is hidden by default (`isRevealed = false`). It shows a "Tap to reveal" placeholder or the `↓` reveal button. |
| C-21 | Tapping the **Reveal** button (or pressing Space — see C-18) sets `isRevealed = true` for this card. |
| C-22 | When `isRevealed == true` and `translationStatus == .translated`, the card shows `"→ \(frenchTranslation)"`. |
| C-23 | When `isRevealed == true` and `translationStatus == .pending`, the card shows a loading indicator ("Translation pending…") instead of the translation text. |
| C-24 | When `isRevealed == true` and `translationStatus == .translated` but `frenchTranslation == nil`, the card shows "Translation unavailable". |
| C-25 | The card exposes three action buttons: **Save** (primary), **Ignore** (secondary/destructive). A third gesture-only action **Known** is accessible via swipe-right (not a visible button in the default state). |
| C-26 | Swipe-left on the card row reveals a destructive **Delete** action (red, calls `onIgnore`). Implemented via `.swipeActions(edge: .trailing, allowsFullSwipe: true)`. |
| C-27 | Swipe-right on the card row reveals a **Known** action (green, calls `onKnown`). Implemented via `.swipeActions(edge: .leading, allowsFullSwipe: true)`. |
| C-28 | `isRevealed` is `@State private var` local to the card. It resets to `false` when the card is removed from the list (the view is destroyed). |
| C-29 | The card's `isRevealed` state is independent of all other cards in the list. |

---

## `StatusItemController` — Badge Extension

### New interface

```swift
/// Start observing the inbox count and update the badge on every change.
/// Must be called once after init, passing the shared repository.
func startBadgeObservation(repository: VocabularyEntryRepository)

/// Update the menu-bar icon button image to show/hide the badge.
/// count = 0 → no badge (restore base icon).
/// count > 0 → compose icon + badge number.
/// Must be called on the main thread.
func updateBadge(count: Int)
```

| # | Contract |
|---|----------|
| C-30 | `startBadgeObservation(repository:)` creates a `ValueObservation` on `fetchInboxCount()` and stores the `Task` in a private property `badgeTask: Task<Void, Never>?`. |
| C-31 | The observation task runs `@MainActor` and calls `updateBadge(count:)` on each update. |
| C-32 | `updateBadge(count:)` MUST be called on the main thread. |
| C-33 | When `count == 0`, `statusItem.button?.image` is restored to the base icon (no badge). |
| C-34 | When `count > 0`, a badge is drawn on top of the base icon. The badge shows the count as a string capped at "9+" for counts > 9. |
| C-35 | Badge drawing uses `NSImage` drawing context: a filled red circle (diameter ~10 pt) overlaid at the bottom-right of the icon, with white text. |
| C-36 | `startBadgeObservation(repository:)` is called from `StatusItemController.init(repository:translationService:)` after `panel` is initialised. |

---

## `VocabularySidebarView` Integration

| # | Contract |
|---|----------|
| C-37 | In `VocabularySidebarView.contentForTab(_:)`, the `.inbox` case is changed from `VocabularyListView(...)` to `InboxView(repository: repository, translationService: translationService)`. |
| C-38 | `VocabularyListView` remains in the codebase unchanged; it is simply no longer the `.inbox` tab host. It can be removed in a future cleanup epic. |

---

## Threading Contracts

| # | Contract |
|---|----------|
| C-39 | All triage actions (`onSave`, `onIgnore`, `onKnown`) are dispatched via `Task { try? repository.markX(id:) }` from the main thread (SwiftUI button action). |
| C-40 | `ValueObservation` tasks in `InboxView` run `@MainActor` — same pattern as all existing observations in the project. |
| C-41 | `StatusItemController.updateBadge(count:)` is always invoked from the `@MainActor` observation task (C-31), satisfying the main-thread requirement (C-32). |
| C-42 | `InboxView` does not call `TranslationService.translate(entry:)` directly. Translation is triggered by the existing `retryPendingOnAppear` view modifier (already applied to `VocabularyListView`; apply the same modifier to `InboxView`). |
