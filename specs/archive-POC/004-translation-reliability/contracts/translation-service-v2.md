# Service Contract: TranslationService (v2 — Translation Reliability)

**Component**: `TranslationService`
**Version**: v2 (amends `specs/003-automated-clipboard-translation/contracts/translation-service.md`)
**Branch**: `004-translation-reliability`

---

## What Changed from v1

| Area | v1 Behaviour | v2 Behaviour |
|------|-------------|-------------|
| Session lifecycle | Session created by `VocabularyListView`'s `.translationTask` modifier (panel must be open) | Session created by `TranslationSessionHost` — a persistent hidden `NSWindow` in `AppDelegate` (initialised at app launch). **Architecture was already correct in current code.** |
| `.translationTask` callback | Calls `configuration?.invalidate()` unconditionally after every session provision → infinite re-trigger loop | `invalidate()` call removed; callback fires naturally on session readiness and model download |
| Retry spinner | `.task(id: retryTrigger)` on value-type view struct — `@State isRetrying` resets on re-render → spinner never stops or disappears prematurely | Explicit `Task {}` launched from button action, stored in `@State var currentRetryTask`; spinner state not tied to view identity |
| `onRetryGroup` closure data source | Passes render-time `group.entries` snapshot (may include already-translated entries) | Calls `retryPendingTranslations()` which fetches live `.pending` entries from DB at execution time |
| `TranslationService` public API | Unchanged | Unchanged |

---

## Interface (unchanged from v1)

```swift
final class TranslationService {

    /// LibreTranslate endpoint used as fallback on macOS < 15.
    /// Defaults to https://libretranslate.com/translate.
    var libreTranslateURL: URL

    /// Optional API key for libretranslate.com free tier.
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
    /// Called from:
    ///   - AppDelegate NWPathMonitor handler (connectivity restored)
    ///   - PersistentTranslationView .translationTask callback (session ready)
    ///   - VocabularyListView onRetryGroup closure (manual retry button)  ← v2 change
    func retryPendingTranslations() async

    /// Re-translate a specific set of entries.
    /// - Returns: Count of entries successfully translated in this batch.
    /// - Throws: TranslationError if the service is wholly unreachable AND no entries succeeded.
    @discardableResult
    func retryGroup(entries: [VocabularyEntry]) async throws -> Int
}
```

---

## Behaviour Contract (cumulative, including v1)

| Condition | Behaviour |
|-----------|-----------|
| Translation succeeds | `frenchTranslation` updated in DB; `translationStatus` set to `'translated'` |
| Network error / service returns non-2xx | Entry left as `pending`; no throw from `translate(entry:)` |
| Malformed / empty response body | `decodingError` caught internally; entry left as `pending` |
| `retryGroup` called with empty array | Returns `0` immediately; no network call |
| `retryGroup`: some succeed, some fail | Returns count of successes; does not throw |
| `retryGroup`: all fail | Throws `TranslationError` so the caller can display an error state |
| `retryPendingTranslations` called when no pending entries | No-op; no network calls |
| Apple session not yet available at capture time | Entry stored as `.pending`; translated when `.translationTask` callback fires (session ready) |
| `.translationTask` callback fires | Sets `appleSession`; calls `retryPendingTranslations()` once; does **not** call `invalidate()` | ← v2 fix |
| Manual retry button tapped | Explicit `Task {}` launched; spinner shown for full task duration regardless of view re-renders | ← v2 fix |
| LibreTranslate URL unreachable or requires API key | Returns non-2xx or network error; `translate()` silently leaves entry as `.pending` |

---

## Session Lifecycle (v2)

```
App launch
  └── AppDelegate.applicationDidFinishLaunching
        └── TranslationSessionHost.install(translationService:)
              └── Creates hidden NSWindow hosting PersistentTranslationView
                    └── .translationTask(configuration) fires (macOS 15+, model ready):
                          1. service.appleSession = session          // inject session
                          2. await service.retryPendingTranslations() // flush pending entries
                          // NOTE: configuration?.invalidate() REMOVED in v2

Connectivity restored
  └── AppDelegate.NWPathMonitor handler
        └── Task { await translationService.retryPendingTranslations() }   // existing path

Manual retry button tapped (VocabularyDateGroupSection)
  └── isRetrying = true
  └── currentRetryTask = Task {
          await translationService.retryPendingTranslations()   // ← v2: fetches fresh pending
          isRetrying = false   // written on MainActor in Task body, not via .task(id:) modifier
      }
```

---

## Retry Trigger Sources (v2)

| Trigger | When | Call site | v2 change? |
|---------|------|-----------|------------|
| Network connectivity restored | `NWPathMonitor` path becomes `.satisfied` | `AppDelegate.startConnectivityMonitor()` | No change |
| Session becomes ready (macOS 15+) | `.translationTask` callback fires in `TranslationSessionHost` | `PersistentTranslationView.translationTask` | Removed `invalidate()` call |
| Manual retry button | User taps "Réessayer" in vocabulary panel | `VocabularyDateGroupSection` button action | Rewired from `.task(id:)` to explicit `Task {}` |

---

## Fallback Path Clarification (FR-007)

On macOS 13–14, `appleSession` is always `nil`. All translations use `translateWithLibreTranslate`.

- If `libreTranslateURL` points to an unreachable host → `URLError` thrown internally → entry stays `.pending`.
- If `libreTranslateURL` points to `libretranslate.com` without an API key → HTTP 403 → `TranslationError.unavailable` → entry stays `.pending`.
- Neither case throws out of `translate(entry:)`. The entry is always left pending for retry.

**The fallback being unavailable or misconfigured does NOT permanently block entries.**

---

## Threading

All public methods are `async`. Internal URLSession calls use Swift concurrency. Database writes after successful translation are synchronous GRDB writes on whatever thread calls them (GRDB `DatabaseQueue` serialises internally). The persistent session host (`TranslationSessionHost`) runs on the main thread (required by SwiftUI/AppKit). Manual retry task state mutations (`isRetrying`, `retryError`) are dispatched to `@MainActor`.
