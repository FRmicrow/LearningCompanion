# Data Model: Automated Clipboard Translation

**Branch**: `003-automated-clipboard-translation` | **Date**: 2025-07-17
**Source**: `spec.md` (entities), `research.md` Decision 5 (storage: SQLite via GRDB.swift)

---

## Entities

### `VocabularyEntry`

The central and only persisted entity. Represents one unique English word or short phrase captured from the clipboard, together with its French translation and capture metadata.

#### Schema

| Column | SQLite Type | Constraints | Description |
|--------|-------------|-------------|-------------|
| `id` | `INTEGER` | PRIMARY KEY, AUTOINCREMENT | Internal surrogate key. |
| `englishText` | `TEXT` | NOT NULL, UNIQUE | Original clipboard text (≤ 50 chars, case-preserved). Uniqueness key for deduplication (FR-007). |
| `frenchTranslation` | `TEXT` | NULLABLE | French translation. `NULL` when `translationStatus = 'pending'`. |
| `translationStatus` | `TEXT` | NOT NULL, DEFAULT `'pending'` | Enum: `'pending'` or `'translated'`. Drives retry eligibility (FR-008). |
| `seenCount` | `INTEGER` | NOT NULL, DEFAULT `1`, CHECK ≥ 1 | Number of times this exact text has been copied. Incremented on each re-capture without creating a duplicate (FR-007). Resets to 1 if entry is deleted and later re-captured. |
| `firstCapturedAt` | `TEXT` | NOT NULL | ISO 8601 UTC timestamp of first capture. Used for chronological ordering. |
| `lastSeenAt` | `TEXT` | NOT NULL | ISO 8601 UTC timestamp of most recent capture (updated on every re-capture). |
| `isRetained` | `INTEGER` | NOT NULL, DEFAULT `0` | Boolean flag (`0`/`1`). Set by the user to mark a word as "learned". Used by the vocabulary panel to surface old unretained words. |

#### Indexes

| Index | Columns | Purpose |
|-------|---------|---------|
| `idx_vocabulary_english_text` | `englishText` | Fast duplicate lookup on every clipboard event |
| `idx_vocabulary_first_captured` | `firstCapturedAt` | Chronological list ordering |
| `idx_vocabulary_translation_status` | `translationStatus` | Efficient pending-retry queue scan (FR-008) |

#### Deduplication Rule

On capture of English text `T`:
1. Query `SELECT * FROM vocabulary_entries WHERE englishText = T` (case-sensitive).
2. **Row exists** → `UPDATE SET seenCount = seenCount + 1, lastSeenAt = now` — no new entry, no translation.
3. **No row** → `INSERT (englishText=T, frenchTranslation=NULL, translationStatus='pending', seenCount=1, firstCapturedAt=now, lastSeenAt=now, isRetained=0)` — then trigger translation.

#### `TranslationStatus` State Machine

```
              [capture eligible text]
                       │
                       ▼
               ┌──────────────┐
               │   pending    │ ◄── translation fails / device offline
               └──────────────┘
                       │
        connectivity restored (NWPathMonitor)
        OR manual retry triggered
                       │
                       ▼
               ┌──────────────┐
               │  translated  │
               └──────────────┘
```

- `pending → translated`: Translation succeeds; `frenchTranslation` is written, `translationStatus` set to `'translated'`.
- `translated → pending`: Not possible — translation is never invalidated once set.
- Any state → **deleted**: User hard-deletes entry. If same text is re-captured later, a fresh row is created with `seenCount = 1`.

#### Validation Rules (application layer)

| Rule | Guard | FR |
|------|-------|----|
| Length gate | `englishText.count ≤ 50` — enforced before INSERT | FR-002 |
| Content gate | Plain text only; URLs, numbers, file paths discarded | FR-003 |
| Language gate | Dominant language = English, confidence ≥ 0.6 | FR-004 |
| Pause gate | Capture skipped entirely when `CaptureState = .paused` | FR-009 |
| Duplicate gate | Upsert logic above; never two rows with same `englishText` | FR-007 |

---

### `CaptureState` (In-Memory Only)

Represents whether clipboard monitoring is currently active or paused. **Never persisted** — always resets to `.active` on app launch (FR-011).

```swift
enum CaptureState {
    case active   // Timer fires + delegate called on clipboard change
    case paused   // Timer fires but delegate is NOT called; text silently dropped
}
```

| State | Transition | Trigger |
|-------|-----------|---------|
| `.active` → `.paused` | `clipboardMonitor.pause()` | User presses ⌘ Shift C or selects "Pause" in menu |
| `.paused` → `.active` | `clipboardMonitor.resume()` | User presses ⌘ Shift C or selects "Resume" in menu |
| App launch | Always starts `.active` | `ClipboardMonitorService` init |

---

## Storage Location

```
~/Library/Application Support/ClipboardVocab/vocabulary.sqlite
```

- Created automatically on first launch (directory created if absent).
- Single-file, zero-configuration SQLite database; no server process.
- Included in Time Machine backups automatically.

---

## Migration History

Schema version tracked via GRDB `DatabaseMigrator` (named migrations, idempotent).

| Migration | Changes |
|-----------|---------|
| `v1` | Initial schema — `vocabulary_entries` table with columns `id`, `englishText`, `frenchTranslation`, `translationStatus`, `seenCount`, `firstCapturedAt`, `lastSeenAt`; three indexes. |
| `v2` | `ALTER TABLE vocabulary_entries ADD COLUMN isRetained INTEGER NOT NULL DEFAULT 0` — adds retained flag for vocabulary panel feature. |

Future migrations must be additive (`ADD COLUMN`) or use a new named migration step — never drop/rename existing columns.
