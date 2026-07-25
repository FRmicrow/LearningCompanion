# Data Model: Inbox — Capture & Triage

**Feature**: 007-inbox-capture-triage  
**Date**: 2025-07-21

---

## Overview

This epic introduces one DB migration (`v3`) that adds a `triageStatus` column to the existing `vocabulary_entries` table. Two lightweight value types are introduced for the UI layer. No new tables are created. The existing `VocabularyEntry` model gains one new field and a new nested enum.

---

## Schema Change — Migration v3

### `vocabulary_entries` — added column

| Column | SQL Type | Constraint | Default |
|--------|----------|-----------|---------|
| `triageStatus` | `TEXT` | `NOT NULL` | `'unreviewed'` |

**SQL**:
```sql
ALTER TABLE vocabulary_entries ADD COLUMN triageStatus TEXT NOT NULL DEFAULT 'unreviewed'
```

**Index**: A partial index on `triageStatus` accelerates the Inbox query and badge count:
```sql
CREATE INDEX idx_vocabulary_triage_status ON vocabulary_entries (triageStatus)
```

**Migration registration**: Registered as `"v3"` in `Database.migrate()`.

---

## Updated Entity — `VocabularyEntry`

`VocabularyEntry` gains one new stored field and a new nested enum.

### New field

| Field | Swift Type | DB Column | Description |
|-------|-----------|-----------|-------------|
| `triageStatus` | `TriageStatus` | `triageStatus` | The user's triage decision for this entry. Defaults to `.unreviewed` on insert. |

### New enum — `VocabularyEntry.TriageStatus`

| Case | Raw Value | Meaning |
|------|-----------|---------|
| `.unreviewed` | `"unreviewed"` | Captured but not yet triaged. Appears in the Inbox. |
| `.saved` | `"saved"` | User tapped **Save**. Entered the vocabulary learning pipeline. |
| `.ignored` | `"ignored"` | User tapped **Ignore** or swiped-left Delete. Not in the learning pipeline. |
| `.known` | `"known"` | User swiped-right Known. Saved with a "already known" marker for future SRS use. |

**Notes**:
- `triageStatus` is independent of `isRetained`. `isRetained` is the legacy "keep/dismiss" flag from the old UI; it may coexist with `triageStatus` without conflict.
- Existing rows in the DB (inserted before migration v3) receive `triageStatus = 'unreviewed'` automatically via the SQL DEFAULT. This means pre-existing entries will appear in the Inbox after upgrade — which is intentional: the user can triage their existing vocabulary.
- `translationStatus` (`.pending` / `.translated`) is orthogonal to `triageStatus`. A word can be `unreviewed` and `translated` (translation arrived before the user opened the Inbox), or `unreviewed` and `pending` (translation still computing).

### Full `VocabularyEntry` field summary (after migration v3)

| Field | Type | Notes |
|-------|------|-------|
| `id` | `Int64?` | Primary key |
| `englishText` | `String` | Source word; `UNIQUE` |
| `frenchTranslation` | `String?` | Nullable until translated |
| `translationStatus` | `TranslationStatus` | `.pending` / `.translated` |
| `triageStatus` | `TriageStatus` | `.unreviewed` / `.saved` / `.ignored` / `.known` — NEW |
| `seenCount` | `Int` | Incremented on duplicate captures |
| `firstCapturedAt` | `Date` | Capture timestamp |
| `lastSeenAt` | `Date` | Last re-capture timestamp |
| `isRetained` | `Bool` | Legacy keep/dismiss flag |

**`CodingKeys` mapping** (camelCase → camelCase, explicit per project convention):
- `triageStatus` → `"triageStatus"`

---

## New Repository Methods

These methods are added to `VocabularyEntryRepository`. All are synchronous, called from a `Task` at the call site.

### `fetchInbox() throws -> [VocabularyEntry]`

Returns all entries with `triageStatus == .unreviewed`, ordered by `firstCapturedAt` descending (most recent first).

```sql
SELECT * FROM vocabulary_entries
WHERE triageStatus = 'unreviewed'
ORDER BY firstCapturedAt DESC
```

### `fetchInboxCount() throws -> Int`

Returns the count of entries with `triageStatus == .unreviewed`. Used by the badge `ValueObservation`.

```sql
SELECT COUNT(*) FROM vocabulary_entries WHERE triageStatus = 'unreviewed'
```

### `markSaved(id:) throws`

Sets `triageStatus = 'saved'` for the given entry. The entry disappears from the Inbox after this call.

```sql
UPDATE vocabulary_entries SET triageStatus = 'saved' WHERE id = ?
```

### `markIgnored(id:) throws`

Sets `triageStatus = 'ignored'` for the given entry.

```sql
UPDATE vocabulary_entries SET triageStatus = 'ignored' WHERE id = ?
```

### `markKnown(id:) throws`

Sets `triageStatus = 'known'` for the given entry.

```sql
UPDATE vocabulary_entries SET triageStatus = 'known' WHERE id = ?
```

---

## New UI Value Types

### `InboxEntry`

A typed view over `VocabularyEntry` scoped to the Inbox context. This is **not** a new DB entity — it is a lightweight struct wrapping a `VocabularyEntry` for display purposes.

| Field | Type | Source |
|-------|------|--------|
| `entry` | `VocabularyEntry` | The underlying DB row |
| `word` | `String` | `entry.englishText` |
| `translation` | `String?` | `entry.frenchTranslation` (nil = not yet translated) |
| `isTranslationAvailable` | `Bool` | `entry.translationStatus == .translated` |

**Notes**: Created inline in `InboxView` from the `ValueObservation` result. Not persisted.

### `BadgeCount`

An integer derived from the `fetchInboxCount` `ValueObservation`. Not stored; computed and forwarded to `StatusItemController.updateBadge(count:)`.

---

## State Transitions — `triageStatus`

```
 [clipboard capture]
        │
        ▼
   unreviewed  ──── Save ──────────► saved
        │
        ├──── Ignore / swipe-left ──► ignored
        │
        └──── swipe-right / Known ──► known
```

- Transitions are **one-way** and **final** within this epic. There is no "undo" mechanism (deferred to Epic 6 polish, if desired).
- A re-capture of an `ignored` or `saved` word increments `seenCount` and updates `lastSeenAt` but does **not** reset `triageStatus` back to `unreviewed` (see Research Decision 2).

---

## Query: Inbox `ValueObservation`

```swift
ValueObservation.tracking { db in
    try VocabularyEntry
        .filter(Column("triageStatus") == VocabularyEntry.TriageStatus.unreviewed.rawValue)
        .order(Column("firstCapturedAt").desc)
        .fetchAll(db)
}
```

Driven from `InboxView.startObservation()` via `Task { @MainActor in ... }`, cancelled in `.onDisappear`. Follows the existing pattern from `VocabularyListView` and `VocabularySidebarView`.

---

## Query: Badge Count `ValueObservation`

```swift
ValueObservation.tracking { db in
    try VocabularyEntry
        .filter(Column("triageStatus") == VocabularyEntry.TriageStatus.unreviewed.rawValue)
        .fetchCount(db)
}
```

Driven from `StatusItemController.startBadgeObservation(repository:)`, called once from `StatusItemController.init`. Fires `updateBadge(count:)` on the main thread on each change.
