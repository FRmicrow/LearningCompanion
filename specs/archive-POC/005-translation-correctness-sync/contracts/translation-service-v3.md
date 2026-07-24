# Service Contract: TranslationService (v3 — Translation Correctness & Sync)

**Component**: `TranslationService`
**Version**: v3 (amends `specs/004-translation-reliability/contracts/translation-service-v2.md`)
**Branch**: `005-translation-correctness-sync`

---

## What Changed from v2

| Area | v2 Behaviour | v3 Behaviour |
|------|-------------|-------------|
| `retryPendingTranslations()` concurrency | No guard — concurrent callers from session-ready, connectivity-restored, and manual retry can overlap, issuing duplicate translation requests for the same entries | **New: in-memory `retryInProgress` flag**. If a retry pass is already in flight when a new trigger fires, the new call returns immediately (no-op). At most one sequential retry pass runs at a time. |
| Public interface | Unchanged | Unchanged |
| Throwing contract | Unchanged | Unchanged |
| Session lifecycle | Unchanged | Unchanged |

---

## Interface (unchanged from v2)

```swift
final class TranslationService {

    /// LibreTranslate endpoint used as fallback on macOS < 15.
    /// Hardwired in AppDelegate to http://localhost:5001/translate (self-hosted Docker, no API key).
    var libreTranslateURL: URL

    /// Optional API key for libretranslate.com free tier. Unused in production (self-hosted has no auth).
    var apiKey: String

    /// Active Apple Translation session (macOS 15+ only). Injected by
    /// PersistentTranslationView inside TranslationSessionHost.
    @available(macOS 15, *)
    var appleSession: TranslationSession?

    /// Translate a single entry. On success, updates `frenchTranslation` and
    /// `translationStatus` in the database. On failure, leaves the entry as
    /// `.pending`. NEVER throws — callers must not use `try`.
    func translate(entry: VocabularyEntry) async

    /// Retry all entries currently stored with `translationStatus = .pending`.
    /// Fetches live pending entries from the DB at call time.
    ///
    /// If a retry pass is already in flight (retryInProgress == true), this call
    /// is a no-op and returns immediately. — v3 addition
    ///
    /// Called from:
    ///   - AppDelegate NWPathMonitor handler (connectivity restored)
    ///   - PersistentTranslationView .translationTask callback (session ready)
    ///   - VocabularyDateGroupSection onRetryGroup closure (manual retry button)
    ///   - AppleTranslationSessionModifier .onAppear (panel opens, catch-up)
    func retryPendingTranslations() async

    /// Re-translate a specific set of entries.
    /// Not affected by the retryInProgress guard (separate, lower-level call path).
    /// - Returns: Count of entries successfully translated in this batch.
    /// - Throws: TranslationError if the service is wholly unreachable AND no entries succeeded.
    @discardableResult
    func retryGroup(entries: [VocabularyEntry]) async throws -> Int
}
```

---

## Behaviour Contract (cumulative, including v1 and v2)

| Condition | Behaviour |
|-----------|-----------|
| Translation succeeds | `frenchTranslation` updated in DB; `translationStatus` set to `'translated'` |
| Network error / service returns non-2xx | Entry left as `pending`; no throw from `translate(entry:)` |
| Malformed / empty response body | `decodingError` caught internally; entry left as `pending` |
| `retryGroup` called with empty array | Returns `0` immediately; no network call |
| `retryGroup`: some succeed, some fail | Returns count of successes; does not throw |
| `retryGroup`: all fail | Throws `TranslationError` so the caller can display an error state |
| `retryPendingTranslations` called when no pending entries | No-op; no network calls |
| `retryPendingTranslations` called while already in flight | No-op; returns immediately (v3 addition) |
| Apple session not yet available at capture time | Entry stored as `.pending`; translated when `.translationTask` callback fires |
| `.translationTask` callback fires | Sets `appleSession`; calls `retryPendingTranslations()` once; does not call `invalidate()` |
| Manual retry button tapped | Explicit `Task {}` launched; spinner shown for full task duration regardless of view re-renders |
| LibreTranslate URL unreachable or requires API key | Returns non-2xx or network error; `translate()` silently leaves entry as `.pending` |

---

## Implementation: concurrency guard (v3 addition)

The guard is implemented as a single `Bool` property on `TranslationService`. Because all callers dispatch through Swift concurrency on the main actor (see Threading below), a simple boolean is race-free:

```swift
private var retryInProgress = false

func retryPendingTranslations() async {
    guard !retryInProgress else { return }
    retryInProgress = true
    defer { retryInProgress = false }
    guard let pending = try? repository.fetchPending() else { return }
    for entry in pending {
        await translate(entry: entry)
    }
}
```

`retryGroup(entries:)` and `translate(entry:)` are **not** guarded by this flag — they are lower-level primitives that callers may invoke independently.

---

## Session Lifecycle (unchanged from v2)

```
App launch
  └── AppDelegate.applicationDidFinishLaunching
        └── TranslationSessionHost.install(translationService:)
              └── Creates hidden NSWindow hosting PersistentTranslationView
                    └── .translationTask(configuration) fires (macOS 15+, model ready):
                          1. service.appleSession = session
                          2. await service.retryPendingTranslations()  // guarded in v3

Connectivity restored
  └── AppDelegate.NWPathMonitor handler
        └── Task { await translationService.retryPendingTranslations() }  // guarded in v3

Manual retry button tapped (VocabularyDateGroupSection)
  └── isRetrying = true
  └── currentRetryTask = Task {
          await translationService.retryPendingTranslations()  // guarded in v3
          isRetrying = false
      }

Panel opens (VocabularyListView.onAppear via AppleTranslationSessionModifier)
  └── Task { await service.retryPendingTranslations() }  // guarded in v3
```

---

## Threading

All public methods are `async`. All current call sites dispatch to `retryPendingTranslations()` through Swift concurrency on or from the main thread. The `retryInProgress` flag requires no additional synchronisation because it is only ever read and written on the same concurrency domain.

Internal `URLSession` calls use Swift concurrency. Database writes after successful translation are synchronous GRDB writes serialised by `DatabaseQueue`. Manual retry task state mutations (`isRetrying`, `retryError`) are dispatched to `@MainActor` from the button action.

---

## Relationship to Prior Versions

- **v1** (`specs/003-automated-clipboard-translation/contracts/translation-service.md`): Original interface definition.
- **v2** (`specs/004-translation-reliability/contracts/translation-service-v2.md`): Fixed session loop, spinner, and stale snapshot.
- **v3** (this file): Adds concurrency guard to `retryPendingTranslations()`. All v2 behaviour is preserved.
