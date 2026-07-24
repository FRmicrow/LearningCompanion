# Service Contract: CaptureProcessor

**Component**: `CaptureProcessorService`
**Direction**: Internal — receives raw text from `ClipboardMonitorService`, applies all filter/gate logic, persists and translates entries
**Source**: `spec.md` FR-001 through FR-008, `research.md` Decisions 3 & 4

---

## Responsibilities

Applies the full capture pipeline to a raw clipboard string:

1. **Length gate** — discard text > 50 characters
2. **Content gate** — discard URLs, numbers, file paths, and other non-natural-language patterns
3. **Language detection** — discard if not English or confidence < 0.6
4. **Deduplication** — increment counter if already in DB; insert new entry otherwise
5. **Translation** — request EN→FR translation for new entries only
6. **Persistence** — entry is always saved before translation completes

---

## Interface

```swift
protocol CaptureProcessorDelegate: AnyObject {
    /// Called when an entry is successfully stored (new insert or counter-incremented).
    func captureProcessor(_ processor: CaptureProcessorService,
                          didStore entry: VocabularyEntry)
    /// Called when text was silently discarded (diagnostic / testing only — no UI shown to user).
    func captureProcessor(_ processor: CaptureProcessorService,
                          didDiscard text: String,
                          reason: DiscardReason)
}

final class CaptureProcessorService {
    weak var delegate: CaptureProcessorDelegate?

    /// Process raw clipboard text through the full capture pipeline.
    /// All work is performed asynchronously. Delegate callbacks on main thread.
    func process(text: String) async
}

enum DiscardReason {
    case tooLong              // > 50 characters
    case noMeaningfulLanguage // numbers-only, URL, Unix/Windows file path, etc.
    case notEnglish           // detected as French or other non-English language
    case lowConfidence        // NLLanguageRecognizer confidence < 0.6
    case duplicate            // same text already existed; seenCount incremented instead
}
```

---

## Pipeline Specification

```
raw text (from ClipboardMonitorService)
    │
    ├─ length > 50 chars? ──────────────────► didDiscard(.tooLong)
    │
    ├─ no natural language content? ────────► didDiscard(.noMeaningfulLanguage)
    │   (numbers, URLs, /unix/paths, C:\win\paths)
    │
    ├─ NLLanguageRecognizer
    │       confidence < 0.6? ─────────────► didDiscard(.lowConfidence)
    │       dominant ≠ .english? ──────────► didDiscard(.notEnglish)
    │
    ├─ duplicate check
    │       exists in DB? ─────────────────► UPDATE seenCount++, lastSeenAt = now
    │                                        → didStore(updatedEntry)
    │
    └─ INSERT new entry (status=pending, seenCount=1)
            │
            └─► TranslationService.translate(entry:)
                    success ─────► UPDATE frenchTranslation, status=translated
                    failure ─────► leave as .pending; retry via NWPathMonitor
                    │
                    └─► didStore(latestEntry)
```

---

## Invariants

| Invariant | Description |
|-----------|-------------|
| **Save-before-translate** | Entry is persisted to SQLite with `status=pending` before any translation attempt. A crash or network failure during translation cannot lose the captured word. |
| **No duplicate rows** | `englishText` has a UNIQUE constraint. The upsert path guarantees at most one row per distinct English text value. |
| **Delegate on main thread** | Both `didStore` and `didDiscard` are always called on the main thread. |
| **Duplicate does not retranslate** | When `seenCount` is incremented, no new translation request is made. |

---

## Translation Retry Contract

- **Automatic retry**: `NWPathMonitor` in `AppDelegate` calls `TranslationService.retryPendingTranslations()` when path status transitions to `.satisfied`.
- **Manual group retry**: `TranslationService.retryGroup(entries:)` re-translates a specific set of entries (used by the vocabulary panel per-group retry button).
- **No retry limit**: Entries remain `pending` indefinitely until translation succeeds or the entry is deleted.
- **Re-translation not supported**: Once `status = translated`, the translation is not re-requested (no invalidation).
