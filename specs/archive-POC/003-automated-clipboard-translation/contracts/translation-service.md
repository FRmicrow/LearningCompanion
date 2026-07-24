# Service Contract: TranslationService

**Component**: `TranslationService`
**Direction**: Internal — called by `CaptureProcessorService` (new entries) and `AppDelegate` (pending retry)
**Source**: `research.md` Decision 4 (translation strategy)

---

## Responsibilities

Translates English text to French using a two-path strategy:

- **macOS 15+**: Apple `Translation` framework (on-device neural translation, private, offline-capable)
- **macOS 13–14**: LibreTranslate HTTP POST (configurable endpoint, defaults to `libretranslate.com`)

On any failure, the entry is left with `translationStatus = .pending` for later retry. The service never throws to callers of `translate(entry:)` — failures are silent (entry stays pending). `retryGroup(entries:)` may throw if the service is wholly unreachable.

---

## Interface

```swift
final class TranslationService {

    /// LibreTranslate endpoint used as fallback on macOS < 15.
    /// Defaults to the public instance; override to point at a self-hosted setup.
    var libreTranslateURL: URL

    /// Translate a single entry. On success, updates `frenchTranslation` and
    /// `translationStatus` in the database. On failure, leaves the entry as `.pending`.
    /// Never throws — callers need not handle errors.
    func translate(entry: VocabularyEntry) async

    /// Retry all entries currently stored with `translationStatus = .pending`.
    /// Called automatically by `AppDelegate` via `NWPathMonitor` on reconnect.
    func retryPendingTranslations() async

    /// Re-translate a specific set of entries regardless of current status.
    /// Used by the vocabulary panel's per-group retry button.
    ///
    /// - Returns: Count of entries successfully translated in this batch.
    /// - Throws: `TranslationError.unavailable` if the service is wholly unreachable
    ///   AND no entries succeeded.
    @discardableResult
    func retryGroup(entries: [VocabularyEntry]) async throws -> Int
}

enum TranslationError: Error {
    case unavailable      // Service unreachable or HTTP status outside 2xx
    case networkError(Error) // URLSession / network-layer error
    case decodingError    // Response could not be parsed
}
```

---

## Behaviour Contract

| Condition | Behaviour |
|-----------|-----------|
| Translation succeeds | `frenchTranslation` updated in DB; `translationStatus` set to `'translated'` |
| Network error / service returns non-2xx | Entry left as `pending`; no throw from `translate(entry:)` |
| Malformed / empty response body | `decodingError` caught internally; entry left as `pending` |
| `retryGroup` called with empty array | Returns `0` immediately; no network call |
| `retryGroup`: some succeed, some fail | Returns count of successes; does not throw |
| `retryGroup`: all fail | Throws `TranslationError` so the caller can display an error state |
| `retryPendingTranslations` called when no pending entries | No-op; no network calls |

---

## Translation Request Format (LibreTranslate)

```http
POST /translate
Content-Type: application/json

{
  "q": "<english text>",
  "source": "en",
  "target": "fr",
  "format": "text"
}
```

Expected successful response:

```json
{
  "translatedText": "<french text>"
}
```

---

## Platform Strategy

| macOS version | Translation path | Notes |
|---------------|-----------------|-------|
| ≥ 15.0 | Apple `Translation` framework | On-device, private, no API key. Language pack download may be required on first use. |
| 13.0 – 14.x | LibreTranslate HTTP | Network required. `libreTranslateURL` must be reachable. |

> **Override for testing**: Set `translationService.libreTranslateURL` to a local mock server to avoid real network calls in tests.

---

## Threading

All public methods are `async` — they must be called from a Swift concurrency context (`Task`, `async` function, or `await`). Internal URLSession calls use Swift concurrency (`URLSession.data(for:)`). Database writes after successful translation are synchronous GRDB calls wrapped in a background context.
