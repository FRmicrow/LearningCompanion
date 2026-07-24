# Service Contract: CaptureProcessor

**Component**: `CaptureProcessorService`
**Direction**: Internal — receives raw text from `ClipboardMonitorService`, applies all filter/gate logic, persists entries
**Source**: `spec.md` FR-003 to FR-017, `research.md` Decisions 3 & 4

---

## Responsibilities

Applies the full capture pipeline to a raw clipboard string:
1. Length gate (≤ 50 chars)
2. Non-language content gate (numbers-only, URLs, file paths)
3. Language detection (English vs. not-English)
4. Deduplication check (increment counter or insert new entry)
5. Translation request (if new entry)
6. Persistence

## Interface

```swift
protocol CaptureProcessorDelegate: AnyObject {
    /// Called when an entry is successfully stored (new or counter-incremented).
    func captureProcessor(_ processor: CaptureProcessorService, didStore entry: VocabularyEntry)
    /// Called when text was silently discarded (for diagnostic/testing purposes only; no UI shown to user).
    func captureProcessor(_ processor: CaptureProcessorService, didDiscard text: String, reason: DiscardReason)
}

final class CaptureProcessorService {
    weak var delegate: CaptureProcessorDelegate?

    /// Process raw clipboard text through the full capture pipeline.
    /// All work is performed asynchronously. Delegate callbacks on main thread.
    func process(text: String) async
}

enum DiscardReason {
    case tooLong             // > 50 characters
    case noMeaningfulLanguage // numbers, URL, file path, etc.
    case notEnglish           // detected as French or other language
    case lowConfidence        // language detection confidence < 0.6
    case duplicate            // same text already exists; counter incremented instead
}
```

## Pipeline Specification

```
raw text
    │
    ├─ length > 50 chars? ──► discard(.tooLong)
    │
    ├─ no natural language content? ──► discard(.noMeaningfulLanguage)
    │
    ├─ language detection
    │       confidence < 0.6? ──► discard(.lowConfidence)
    │       dominant != .english? ──► discard(.notEnglish)
    │
    ├─ duplicate check
    │       exists in DB? ──► increment seenCount + lastSeenAt ──► delegate.didStore (updated)
    │
    └─ INSERT new entry (translationStatus = .pending, seenCount = 1)
            │
            └─► trigger TranslationService.translate(entry:)
                    success ──► update frenchTranslation, status = .translated
                    failure ──► leave as .pending; background retry scheduled
```

## Translation Retry Contract

- On app foreground / connectivity change: scan for all entries with `translationStatus = 'pending'` and retry in sequence.
- Manual retry (FR-017): user taps retry on a specific entry → `TranslationService.translate(entry:)` called directly.
- No retry limit for v1 (entry remains pending indefinitely until translation succeeds or entry is deleted).
