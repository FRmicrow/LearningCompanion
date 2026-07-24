# Data Model: Translation Reliability

**Branch**: `004-translation-reliability` | **Date**: 2025-07-18
**Depends on**: `research.md`

---

## Overview

No schema changes are required for this feature. The existing `vocabulary_entries` table and `VocabularyEntry` model fully support all new behaviour. This document records the model state as-is and annotates which fields are exercised by the new lifecycle paths.

---

## Entity: VocabularyEntry

**Table**: `vocabulary_entries`
**Swift type**: `VocabularyEntry` (struct, `ClipboardVocab/Models/VocabularyEntry.swift`)

| Field | SQL column | Type | Nullable | Default | Role in this feature |
|-------|-----------|------|----------|---------|---------------------|
| `id` | `id` | INTEGER (autoincrement PK) | No | — | Identity; used when refetching after translation |
| `englishText` | `englishText` | TEXT (unique) | No | — | Input to translation engine |
| `frenchTranslation` | `frenchTranslation` | TEXT | Yes | NULL | Written by `translate()` on success; drives UI display |
| `translationStatus` | `translationStatus` | TEXT | No | `'pending'` | Read by `fetchPending()` to find retry candidates; written to `'translated'` on success |
| `seenCount` | `seenCount` | INTEGER | No | `1` | Unchanged by this feature |
| `firstCapturedAt` | `firstCapturedAt` | DATETIME | No | — | Unchanged by this feature |
| `lastSeenAt` | `lastSeenAt` | `DATETIME` | No | — | Unchanged by this feature |
| `isRetained` | `isRetained` | BOOLEAN | No | `false` | Unchanged by this feature |

### TranslationStatus enum

```swift
enum TranslationStatus: String, Codable {
    case pending    = "pending"    // awaiting translation
    case translated = "translated" // frenchTranslation is populated
}
```

### State transitions relevant to this feature

```
[entry upserted by CaptureProcessorService]
     |
     v
translationStatus = .pending
frenchTranslation = nil
     |
     +-- translate(entry:) / retryPendingTranslations() / retryGroup(entries:)
     |          |
     |          +-- success --> translationStatus = .translated, frenchTranslation = "<text>"
     |          |               [GRDB ValueObservation fires → VocabularyListView updates row]
     |          |
     |          +-- failure --> translationStatus unchanged (.pending), frenchTranslation unchanged (nil)
     |
     v
[remains .pending until next retry opportunity]
```

### Retry trigger sources (v2 — changes to existing wiring, no new triggers)

| Trigger | When | Call site | v2 change |
|---------|------|-----------|-----------|
| Network connectivity restored | `NWPathMonitor` path becomes `.satisfied` | `AppDelegate.startConnectivityMonitor()` | No change |
| Session becomes ready (macOS 15+) | `.translationTask` callback fires in `TranslationSessionHost` | `PersistentTranslationView` | Removed `invalidate()` that caused infinite re-trigger |
| Manual retry button | User taps "Réessayer" in panel | `VocabularyDateGroupSection` button action | Rewired from `.task(id: retryTrigger)` to explicit `Task {}`; closure now calls `retryPendingTranslations()` instead of passing stale `group.entries` |

---

## Persistent Session Host (already present — no structural change)

`TranslationSessionHost` already exists as a persistent hidden `NSWindow` hosting `PersistentTranslationView`. It is created in `AppDelegate.applicationDidFinishLaunching` via `TranslationSessionHost.install(translationService:)`. **No structural changes are needed.** Only the `configuration?.invalidate()` call inside its `.translationTask` callback is removed.

---

## Unchanged Structures

- `VocabularyEntryRepository` — no new methods; `fetchPending()` already exists and is used by retry.
- `TranslationService` — no logic changes; `retryPendingTranslations()` and `retryGroup(entries:)` already exist.
- `CaptureProcessorService` — unchanged; still calls `translate(entry:)` immediately after upsert.
- `Database` schema — no new migration (`v2` is the current head).

---

## GRDB Column Key Reference

Column strings used in queries (camelCase, matching SQL column names — **not** snake_case):

```swift
Column("englishText")
Column("translationStatus")
Column("firstCapturedAt")
Column("isRetained")
```
