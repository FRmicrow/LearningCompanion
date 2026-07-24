# Data Model: Translation Correctness & Sync

**Branch**: `005-translation-correctness-sync` | **Date**: 2025-07-18
**Depends on**: `research.md`

---

## Overview

No schema changes are required for this feature. The existing `vocabulary_entries` table and `VocabularyEntry` model are unchanged and fully support all new behaviour.

The only structural change in this feature is the addition of an in-memory concurrency flag inside `TranslationService` (`retryInProgress: Bool`). This flag is not persisted to the database; it lives only for the lifetime of the running process.

---

## Entity: VocabularyEntry (unchanged)

**Table**: `vocabulary_entries`
**Swift type**: `VocabularyEntry` (struct, `ClipboardVocab/Models/VocabularyEntry.swift`)

| Field | SQL column | Type | Nullable | Default | Notes |
|-------|-----------|------|----------|---------|-------|
| `id` | `id` | INTEGER (autoincrement PK) | No | — | Unchanged |
| `englishText` | `englishText` | TEXT (unique) | No | — | Unchanged |
| `frenchTranslation` | `frenchTranslation` | TEXT | Yes | NULL | Written to on translation success |
| `translationStatus` | `translationStatus` | TEXT | No | `'pending'` | Read by `fetchPending()`; written to `'translated'` on success |
| `seenCount` | `seenCount` | INTEGER | No | `1` | Unchanged |
| `firstCapturedAt` | `firstCapturedAt` | DATETIME | No | — | Unchanged |
| `lastSeenAt` | `lastSeenAt` | DATETIME | No | — | Unchanged |
| `isRetained` | `isRetained` | BOOLEAN | No | `false` | Unchanged |

### TranslationStatus enum (unchanged)

```swift
enum TranslationStatus: String, Codable {
    case pending    = "pending"    // awaiting translation
    case translated = "translated" // frenchTranslation is populated
}
```

### State transition diagram

```
[CaptureProcessorService upserts entry]
      |
      v
translationStatus = .pending
frenchTranslation = nil
      |
      +-- translate(entry:) called
      |         |
      |         +-- success → translationStatus = .translated
      |         |             frenchTranslation = "<text>"
      |         |             [GRDB ValueObservation fires → VocabularyListView updates row]
      |         |
      |         +-- failure → translationStatus unchanged (.pending)
      |                       frenchTranslation unchanged (nil)
      |
      v
[remains .pending until next retry trigger]
```

---

## In-Memory State: TranslationService concurrency guard

**Location**: `ClipboardVocab/Services/TranslationService.swift`
**Not persisted** — exists only while the app is running.

| Property | Type | Purpose |
|----------|------|---------|
| `retryInProgress` | `Bool` | Guards `retryPendingTranslations()` against concurrent re-entry. `true` while a retry pass is in flight; `false` otherwise. |

**Lifecycle**:
- Initialised to `false` at `TranslationService.init`.
- Set to `true` at entry to `retryPendingTranslations()`.
- Reset to `false` in `defer` at exit from `retryPendingTranslations()` (success or failure).
- NOT shared with `retryGroup(entries:)` or `translate(entry:)` — those methods are unaffected.

**Invariant**: At most one sequential pass through `fetchPending()` + per-entry `translate(entry:)` is in flight at any given time. Additional trigger events during an in-flight pass are silently dropped.

---

## Retry Trigger Sources (v3 — same triggers as v2, now with concurrency guard)

| Trigger | When | Call site | v3 change |
|---------|------|-----------|-----------|
| Network connectivity restored | `NWPathMonitor` path becomes `.satisfied` | `AppDelegate.startConnectivityMonitor()` | No change to call site — dropped by guard if already in flight |
| Session becomes ready (macOS 15+) | `.translationTask` callback in `TranslationSessionHost` | `PersistentTranslationView` | No change to call site — dropped by guard if already in flight |
| Manual retry button | User taps "Réessayer" | `VocabularyDateGroupSection` button action | No change to call site — dropped by guard if already in flight |
| Panel opens (catch-up) | `VocabularyListView.onAppear` | `AppleTranslationSessionModifier` | No change to call site — dropped by guard if already in flight |

---

## GRDB Column Key Reference (unchanged)

Column strings used in queries (camelCase, matching SQL column names — not snake_case):

```swift
Column("englishText")
Column("translationStatus")
Column("firstCapturedAt")
Column("isRetained")
```

---

## Database schema (current — v2, unchanged)

No new migration is required. The current schema head is `"v2"` as registered in `Database.migrate()`. This feature adds no columns and changes no table structure.
