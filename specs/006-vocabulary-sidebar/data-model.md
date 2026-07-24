# Data Model: Vocabulary Sidebar — Native Panel

**Feature**: 006-vocabulary-sidebar  
**Date**: 2025-07-15

---

## Overview

This epic introduces no new database tables or migrations. All new entities are **in-memory value types** used exclusively within the UI layer. The existing `VocabularyEntry` model and `vocabulary_entries` table are read-only from this epic's perspective.

---

## New Entities

### `SidebarTab`

A pure Swift enum representing the four navigation destinations of the sidebar panel.

| Field | Type | Description |
|-------|------|-------------|
| `inbox` | case | The Inbox view — new captured words awaiting triage. |
| `learn` | case | The Learn view — guided vocabulary learning (shell only in this epic). |
| `review` | case | The Review view — flashcard-style revision (shell only in this epic). |
| `stats` | case | The Statistics view — learning progress overview (shell only in this epic). |

**Notes**:
- Conforms to `Hashable`, `CaseIterable` for use in the tab bar `ForEach`.
- No persistence required; the selected tab resets to `.inbox` on app relaunch (in-session memory only per spec).
- Each case carries a display label (e.g. `"Inbox"`) and an SF Symbol name (e.g. `"tray"`) used by the tab bar.

---

### `DailyProgress`

An in-memory value type holding today's vocabulary progress, derived from a live `ValueObservation` query.

| Field | Type | Description |
|-------|------|-------------|
| `count` | `Int` | Number of `VocabularyEntry` rows with `firstCapturedAt` within today's calendar day. |
| `target` | `Int` | Fixed daily target. Constant value: `20`. |

**Computed properties**:
- `fraction: Double` — `Double(count) / Double(target)`, clamped to `0.0...1.0`. Used to drive the `ProgressView` value.
- `label: String` — Formatted as `"\(count) / \(target) words"`.

**Notes**:
- Not persisted. Recomputed on every `ValueObservation` update.
- `target` is a compile-time constant in this epic; not user-configurable.

---

## Existing Entities — Unchanged

### `VocabularyEntry` (read in this epic, not mutated)

No schema changes. The sidebar reads entries for the Inbox tab via the existing `ValueObservation` pattern already used in `VocabularyListView`. The `firstCapturedAt` field is used to compute `DailyProgress.count`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `Int64?` | Primary key |
| `englishText` | `String` | Source word |
| `frenchTranslation` | `String?` | Nullable until translated |
| `translationStatus` | `TranslationStatus` | `.pending` or `.translated` |
| `seenCount` | `Int` | Incremented on duplicate captures |
| `firstCapturedAt` | `Date` | Used for progress count and grouping |
| `lastSeenAt` | `Date` | Updated on each duplicate capture |
| `isRetained` | `Bool` | User's keep/ignore flag |

---

## State Transitions

### Tab navigation

```
         ┌─────────────────────────────────────────┐
         │              SidebarTab                  │
         │                                          │
  ┌──────▼──────┐  tab tap / ⌘L  ┌────────────┐   │
  │    inbox    │◄───────────────►│   learn    │   │
  └──────┬──────┘                └────────────┘   │
         │  tab tap / ⌘R                           │
         │                        ┌────────────┐   │
         └───────────────────────►│   review   │   │
                                  └────────────┘   │
                        tab tap   ┌────────────┐   │
         ──────────────────────►  │   stats    │   │
                                  └────────────┘   │
         └─────────────────────────────────────────┘
```

All transitions are immediate (no animation in this epic). The state lives in `@State var selectedTab: SidebarTab` inside `VocabularySidebarView`.

### Panel visibility

```
hidden ──(hotkey / menu-bar click)──► visible
visible ──(hotkey / Escape)──────────► hidden
```

Managed by `VocabularySidebarPanel.toggle()` called from `StatusItemController`.

---

## Query: Daily Progress Count

```sql
SELECT COUNT(*) 
FROM vocabulary_entries 
WHERE firstCapturedAt >= <start of today>
  AND firstCapturedAt < <start of tomorrow>
```

Driven by a `ValueObservation` so it updates reactively when new entries are inserted. No new repository method is strictly required — can be computed inside the view's observation closure using a `filter` on the already-observed `[VocabularyEntry]` array.
