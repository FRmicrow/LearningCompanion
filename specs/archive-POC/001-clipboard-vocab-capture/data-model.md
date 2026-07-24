# Data Model: Clipboard Vocabulary Capture

**Branch**: `001-clipboard-vocab-capture` | **Date**: 2025-07-18
**Source**: `spec.md` (entities), `research.md` (storage decision: SQLite via GRDB.swift)

---

## Entities

### `VocabularyEntry`

The central and only entity. Represents one unique English word or short phrase captured from the clipboard, together with its French translation and metadata.

#### Schema

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `INTEGER` | PRIMARY KEY, AUTOINCREMENT | Internal surrogate key |
| `englishText` | `TEXT` | NOT NULL, UNIQUE | Original clipboard text (≤ 50 chars). Uniqueness key for deduplication (FR-009). Stored as captured (case-preserved). |
| `frenchTranslation` | `TEXT` | NULLABLE | French translation. NULL when `translationStatus = .pending`. |
| `translationStatus` | `TEXT` | NOT NULL, DEFAULT `'pending'` | Enum: `'translated'` or `'pending'`. Drives UI badge and retry eligibility (FR-015). |
| `seenCount` | `INTEGER` | NOT NULL, DEFAULT `1`, CHECK ≥ 1 | Number of times this exact English text has been copied. Incremented on each re-capture (FR-009). Resets to 1 if entry is deleted and re-captured (Clarification session). |
| `firstCapturedAt` | `TEXT` | NOT NULL | ISO 8601 UTC timestamp of first capture. Used for chronological ordering in the vocabulary list. |
| `lastSeenAt` | `TEXT` | NOT NULL | ISO 8601 UTC timestamp of most recent capture. Updated on every re-capture even though no new entry is created. |

#### Indexes

| Index | Columns | Purpose |
|-------|---------|---------|
| `idx_vocabulary_english_text` | `englishText` | Fast duplicate lookup on every clipboard event |
| `idx_vocabulary_first_captured` | `firstCapturedAt` | Chronological list ordering |
| `idx_vocabulary_translation_status` | `translationStatus` | Efficient pending-retry queue scan (FR-016) |

#### Deduplication Rule

On capture of English text `T`:
1. Query `SELECT id, seenCount FROM vocabulary_entries WHERE englishText = T` (case-sensitive match).
2. **If row exists**: `UPDATE SET seenCount = seenCount + 1, lastSeenAt = now WHERE id = ...` — no new entry created.
3. **If no row**: `INSERT INTO vocabulary_entries (englishText, frenchTranslation, translationStatus, seenCount, firstCapturedAt, lastSeenAt) VALUES (T, NULL, 'pending', 1, now, now)` — then trigger translation.

#### State Transitions

```
             [capture]
                │
                ▼
        ┌──────────────┐
        │   pending    │◄── translation fails / offline
        └──────────────┘
                │
    connectivity restored /
    manual retry (FR-016/017)
                │
                ▼
        ┌──────────────┐
        │  translated  │
        └──────────────┘
```

- `pending → translated`: Translation succeeds; `frenchTranslation` is written, `translationStatus` set to `'translated'`.
- `translated → pending`: Not possible once translated (translation is not invalidated).
- Any state → deleted: User deletes entry (FR-012). Row is hard-deleted. If same text is re-captured later, a fresh row is created with `seenCount = 1`.

#### Validation Rules (enforced at application layer, not just DB)

| Rule | Check |
|------|-------|
| Length gate | `englishText.count ≤ 50` — enforced before INSERT (FR-014) |
| Language gate | Dominant language = English, confidence ≥ 0.6 — enforced before INSERT (FR-003) |
| Non-text gate | Content must be plain text (`NSPasteboardTypeString`) — enforced before language detection (FR-006) |
| Pause gate | Capture skipped entirely when `CaptureState = .paused` (FR-018) |
| Duplicate gate | Upsert logic above; never two rows with same `englishText` |

---

## Storage Location

```
~/Library/Application Support/ClipboardVocab/vocabulary.sqlite
```

- Created automatically on first launch.
- Single-file database; no server process.
- Backed up automatically by Time Machine and iCloud Drive (if user has Application Support in backup scope).

---

## In-Memory State (not persisted)

These values are held in application memory only and reset on every launch:

| State | Type | Description |
|-------|------|-------------|
| `CaptureState` | enum `.active` / `.paused` | Whether clipboard monitoring is currently active (FR-018). Always starts as `.active` on launch (FR-020). |
| `lastChangeCount` | `Int` | Last observed `NSPasteboard.changeCount`; used to detect new clipboard events. |

---

## Migration Strategy

Schema version tracked via `PRAGMA user_version` in SQLite.

| Version | Changes |
|---------|---------|
| 1 | Initial schema — `vocabulary_entries` table as above |

Future columns must be added via `ALTER TABLE ADD COLUMN` migrations gated on `user_version` check at startup.
