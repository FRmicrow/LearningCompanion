# Data Model: Vocabulary Panel UI

**Branch**: `002-vocabulary-panel-ui` | **Date**: 2025-07-22
**Source**: `spec.md` entities + `research.md` Decisions 1–3
**Extends**: `specs/001-clipboard-vocab-capture/data-model.md` (schema v1)

---

## Schema Change — v2 Migration

A single column is added to the existing `vocabulary_entries` table.

### New Column: `isRetained`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `isRetained` | `INTEGER` | NOT NULL, DEFAULT `0` | Boolean. `1` = user has checked the "ok" checkbox; `0` = not yet retained. Existing rows receive `0` automatically after migration. |

**Migration identifier**: `"v2"` registered in `DatabaseMigrator` inside `Database.migrate()`.

```sql
-- v2 migration (applied by GRDB DatabaseMigrator)
ALTER TABLE vocabulary_entries ADD COLUMN isRetained INTEGER NOT NULL DEFAULT 0;
```

No new indexes are required — the old-unretained filter combines `isRetained` with a date comparison that is already served by `idx_vocabulary_first_captured`.

---

## Updated Entity: `VocabularyEntry`

Extends the v1 model with one new field.

### Full Field Set (v2)

| Swift Field | Column | Type | Notes |
|-------------|--------|------|-------|
| `id` | `id` | `Int64?` | PK, autoincrement |
| `englishText` | `englishText` | `String` | Original clipboard text, unique |
| `frenchTranslation` | `frenchTranslation` | `String?` | NULL until translated |
| `translationStatus` | `translationStatus` | `TranslationStatus` | `.pending` / `.translated` |
| `seenCount` | `seenCount` | `Int` | ≥ 1 |
| `firstCapturedAt` | `firstCapturedAt` | `Date` | ISO 8601, set on insert |
| `lastSeenAt` | `lastSeenAt` | `Date` | Updated on re-capture |
| **`isRetained`** | **`isRetained`** | **`Bool`** | **NEW** — `false` by default |

---

## Derived Views (computed in Swift, not persisted)

### `DateGroup`

A logical grouping produced by the view layer; not a database table.

| Property | Type | Derivation |
|----------|------|------------|
| `dateLabel` | `String` | Formatted string of the calendar day, e.g. "22 juillet 2025" |
| `calendarDay` | `DateComponents` | `{year, month, day}` from `firstCapturedAt` |
| `entries` | `[VocabularyEntry]` | All entries whose `firstCapturedAt` falls on this day, ordered most-recent-first within the group |

**Grouping algorithm** (Swift):
```
let grouped = Dictionary(grouping: entries) { entry in
    Calendar.current.dateComponents([.year, .month, .day], from: entry.firstCapturedAt)
}
// Sort groups newest-first by their dateComponents
```

### `OldUnretainedList`

A filtered subset produced by the view layer; not a database table.

| Property | Type | Derivation |
|----------|------|------------|
| `cutoff` | `Date` | `Date().addingTimeInterval(-7 * 24 * 3600)` at observation time |
| `entries` | `[VocabularyEntry]` | All entries where `isRetained == false && firstCapturedAt < cutoff` |

---

## State Transitions (extended)

```
              [capture]
                 │
                 ▼
         ┌──────────────┐
         │   pending    │◄── translation fails / offline
         └──────────────┘
                 │
     connectivity restored /
     manual retry / group retry
                 │
                 ▼
         ┌──────────────┐       [user checks "ok"]        ┌──────────────┐
         │  translated  │ ──────────────────────────────► │   retained   │
         └──────────────┘                                 └──────────────┘
                 │                                                │
                 │                                   [user unchecks "ok"]
                 │                                                │
                 └─────────────────────────────────◄─────────────┘

         Any state → deleted: hard-delete from DB (unchanged from v1)
```

- `isRetained = false` (default): Entry appears in its date group. If older than 7 days, also appears in OldUnretainedList.
- `isRetained = true`: Entry remains visible in its date group (styled as checked). Excluded from OldUnretainedList.
- `isRetained` toggle is reversible (user can uncheck).

---

## Repository Operations (new / changed)

| Method | Signature | Description |
|--------|-----------|-------------|
| `markRetained` | `func markRetained(id: Int64, _ retained: Bool) throws` | Sets `isRetained` for a single entry. Used by checkbox toggle. |
| `fetchOldUnretained` | `func fetchOldUnretained(before cutoff: Date) throws -> [VocabularyEntry]` | Returns entries where `isRetained = 0 AND firstCapturedAt < cutoff`. Used by OldUnretainedList. Optional — may be replaced by Swift-side filter on the full `fetchAll` result (see research.md Decision 3). |

The existing `fetchAll()`, `fetchPending()`, `upsert()`, `update()`, `delete()` methods are unchanged.

---

## Migration Strategy (updated)

| Version | Changes |
|---------|---------|
| 1 | Initial schema — `vocabulary_entries` table (id, englishText, frenchTranslation, translationStatus, seenCount, firstCapturedAt, lastSeenAt) |
| **2** | **Add `isRetained INTEGER NOT NULL DEFAULT 0` to `vocabulary_entries`** |

GRDB's `DatabaseMigrator` applies migrations in registration order and tracks them in a `grdb_migrations` table. Migration v2 runs automatically on first launch after update.
