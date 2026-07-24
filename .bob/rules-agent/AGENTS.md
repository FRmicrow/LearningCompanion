# Agent Coding Rules (Non-Obvious Only)

- `TranslationService.translate(entry:)` is declared `async`, not `async throws` — never add `try` at the call site; errors are silently swallowed inside the method.
- `retryGroup(entries:)` **does** throw — only when `successCount == 0`. A mix of success/failure returns a count without throwing.
- GRDB `Column("fieldName")` keys must match the **SQL column names** declared in migrations (`englishText`, `frenchTranslation`, etc.) — they happen to be camelCase, not snake_case; using the wrong casing silently returns empty results.
- `VocabularyEntry.CodingKeys` are declared but map camelCase → same camelCase (kept explicit for future migration safety); do not change them to snake_case without updating migrations.
- `Database(path: ":memory:")` accepts the special SQLite in-memory path string directly — use this in every test `makeRepo()` helper, never use a tmp file path.
- Adding a new migration: register as `"v3"`, `"v4"`, etc. in `Database.migrate()` via `migrator.registerMigration`. Migrations are forward-only; no rollback mechanism exists.
- `GlobalShortcutManager` uses `Unmanaged.passUnretained(self).toOpaque()` in the Carbon callback — the singleton must remain alive for the app lifetime; never hold a local reference.
- `CaptureProcessorService` delegate methods are `@MainActor` — if you add new `notify*` helpers, mark them `@MainActor` and call them with `await`.
- `VocabularyListView` uses `Task { @MainActor in ... }` with an `AsyncSequence` from `ValueObservation.values(in:)` — the observation task is stored in `@State` and cancelled in `.onDisappear`; follow this pattern for any additional observations.
- All localised strings must go through `L10n.string(_:)` in `ClipboardVocab/Models/L10n.swift`, which resolves `Bundle.module` — bare `NSLocalizedString` will produce the key string at runtime in SPM builds.
- `VocabularyEntryRepository.dbQueue` is `internal` (not `private`) by design — `VocabularyListView` uses it directly for `ValueObservation`. Do not tighten the access level.
- `AppDelegate` sets `libreTranslateURL = URL(string: "http://localhost:5001/translate")!` (self-hosted Docker, port 5001, no API key). The `TranslationService` class default (`libretranslate.com`) is never used in production.
- `TranslationSessionHost` must be installed once via `TranslationSessionHost.install(translationService:)` in `applicationDidFinishLaunching`. It uses a zero-size `NSWindow` with `alphaValue = 0` + `orderFrontRegardless()` — the "show" call is required for SwiftUI `.translationTask` to fire on the off-screen view.
- `LanguageDetectionService.confidenceThreshold` is `0.6` — texts below this are discarded as `.lowConfidence`, not `.notEnglish`. Use the constant, not a literal.
