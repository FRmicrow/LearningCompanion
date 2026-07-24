# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Stack

Swift Package Manager, macOS 13+, no Xcode project file — `Package.swift` is the only build manifest.

## Commands

```bash
swift build                                          # build
swift test                                           # run all tests
swift test --filter VocabularyEntryRepository        # run single test suite
swift test --filter CaptureProcessor                 # run single test suite
swift test --filter TranslationService               # run single test suite
swift test --filter ClipboardMonitor                 # run single test suite
swift test --filter LanguageDetection                # run single test suite
swift test --filter CaptureToStorage                 # run integration tests
```

Filter matches against `@Suite(...)` name or type name. There is no linter configured.

## Architecture

Menu-bar-only app (`LSUIElement = YES`, no Dock icon). Wiring happens entirely in `AppDelegate`.

Pipeline: `ClipboardMonitorService` (500 ms poll) → `CaptureProcessorService` (6-step filter) → `VocabularyEntryRepository` (GRDB upsert) → `TranslationService` (LibreTranslate HTTP / Apple Translation on macOS 15+).

Live UI updates come exclusively from **GRDB `ValueObservation`** in `VocabularyListView` — do not use `NotificationCenter` or manual refresh.

`AppDelegate` hardwires `libreTranslateURL` to `http://localhost:5001/translate` (self-hosted Docker, no API key). The class default (`libretranslate.com`) is only a fallback — tests override via `service.libreTranslateURL = URL(string: "http://127.0.0.1:1")!` to force failure.

`TranslationSessionHost.install(translationService:)` must be called once in `applicationDidFinishLaunching`. It creates an invisible zero-size `NSWindow` (`alphaValue = 0`, `orderFrontRegardless()`) to keep the Apple `TranslationSession` alive — the window **must** be "shown" for SwiftUI `onAppear`/`.translationTask` to fire.

## Critical Patterns

- **`TranslationService.translate(entry:)` NEVER throws** — failures leave the entry as `.pending`; only `retryGroup(entries:)` throws (and only when `successCount == 0`). Never add `try` at call sites of `translate(entry:)`.
- **`ClipboardMonitorService` timer keeps firing during pause** — only the delegate call is suppressed. Do not cancel/recreate the timer on toggle.
- **Localization**: always use `L10n.string(_:)` (in `ClipboardVocab/Models/L10n.swift`) instead of bare `NSLocalizedString`. Using `Bundle.main` breaks in SPM executables; `L10n` resolves to `Bundle.module`.
- **Global hotkey**: implemented via Carbon `RegisterEventHotKey`, not the `KeyboardShortcuts` SPM package (removed to fix `#Preview` build failures in CLI/CI).
- **GRDB queries**: use `Column("fieldName")` string keys — `VocabularyEntry.CodingKeys` maps camelCase Swift to camelCase SQL column names (not snake_case despite convention).
- **In-memory DB for tests**: `Database(path: ":memory:")` — pass the resulting `.dbQueue` to `VocabularyEntryRepository`.
- **Delegate callbacks** from `CaptureProcessorService` are dispatched to the main thread via `@MainActor` private helpers — callers must not re-dispatch.
- **`captureState` is always `.active` on init** — pause state is never persisted across restarts.

- **`specs/`** contains 4 numbered spec directories (001–004), each with `contracts/` sub-files that define the authoritative public API and threading contracts for each service. When in doubt, read the relevant contract file.

## Testing Conventions

- Uses **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — not XCTest. Do not mix the two frameworks.
- Test actor types (e.g. `CaptureProcessorTests`) implement delegate protocols directly; `nonisolated` delegate methods dispatch mutations back via `Task { await self.appendX(...) }`.
- After async pipeline calls, tests sleep 100–200 ms (`Task.sleep(nanoseconds:)`) for delegate callbacks to settle before asserting.
- All test targets live under `Tests/` (both `Unit/` and `Integration/`) — the `testTarget` path in `Package.swift` is `"Tests"` (flat, both subdirs included).
