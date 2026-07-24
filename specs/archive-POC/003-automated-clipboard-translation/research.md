# Research: Automated Clipboard Translation

**Branch**: `003-automated-clipboard-translation` | **Date**: 2025-07-17
**Feeds into**: `plan.md`, `data-model.md`, `contracts/`

> **Note**: This feature is the formal specification of the already-implemented ClipboardVocab capture pipeline. The technology decisions documented here were validated against the live codebase in `ClipboardVocab/`. Decisions from `specs/001-clipboard-vocab-capture/research.md` are reproduced here and cross-referenced for traceability.

---

## Decision 1: Application Framework / Language

**Decision**: Swift 5.9+ with AppKit, packaged as a Swift Package Manager project

**Rationale**: The spec mandates a macOS menu bar app with minimal resource footprint (< 1% CPU, < 50 MB RAM), a global keyboard shortcut, and deep OS integration (clipboard monitoring, system tray). Swift with AppKit is the natural choice: it ships with macOS, produces small binaries with no runtime install, and provides first-class APIs for every required capability (`NSStatusBar`, `NSPasteboard`, Carbon hotkey registration). See `specs/001/research.md Decision 1` for the full alternatives analysis.

**Alternatives considered**:
- **Electron**: ~200–400 MB RAM baseline — violates SC-005 by an order of magnitude.
- **Python + rumps**: Requires a bundled Python runtime; startup latency and binary size are worse.
- **Tauri (Rust + WebView)**: macOS menu bar and `NSPasteboard` APIs are less mature in the Rust ecosystem.

---

## Decision 2: Clipboard Monitoring Strategy

**Decision**: Poll `NSPasteboard.general.changeCount` on a background `DispatchSourceTimer` at 500 ms intervals

**Rationale**: macOS provides no push-notification API for cross-application clipboard changes. The `changeCount` polling pattern is the industry standard used by Raycast, Pastebot, and ClipMenu. A 500 ms interval is imperceptible to users while keeping CPU near zero (a single integer comparison per tick). The timer runs on a dedicated background `DispatchQueue`; the delegate callback is dispatched to the main thread. When paused, the timer continues firing but the delegate is not called — no timer destruction/recreation overhead on toggle. See `specs/001/research.md Decision 2`.

**Alternatives considered**:
- **Distributed NSNotification**: macOS does not post a public notification on clipboard change.
- **IOHIDManager keyboard intercept**: Misses clipboard writes from drag-and-drop, context menus, and programmatic APIs.
- **1-second polling**: Acceptable but halves responsiveness for fast copy-translate-paste workflows.

---

## Decision 3: Language Detection

**Decision**: Apple `NaturalLanguage` framework (`NLLanguageRecognizer`), on-device, confidence threshold 0.6

**Rationale**: `NLLanguageRecognizer` runs entirely on-device with no network call. It returns the dominant language and a confidence score, handles single words reasonably well, and is free/private. Clipboard text never leaves the device for detection. The 0.6 confidence threshold was validated empirically against a corpus of English and French text (SC-003: > 95% accuracy for unambiguous input). Texts below the threshold are silently discarded rather than misclassified. See `specs/001/research.md Decision 3`.

**Handling mixed-language text**: For texts ≤ 50 characters with mixed signals (e.g., "c'est awesome"), the dominant-language classification is used; if not English, the entry is ignored — consistent with FR-004.

**Alternatives considered**:
- **fastText bundled model**: Adds binary size with no advantage for EN/FR discrimination.
- **Remote language detection API**: Adds latency, network dependency, and privacy risk.

---

## Decision 4: Translation Service

**Decision**: Dual-path strategy — Apple `Translation` framework (macOS 15+) with LibreTranslate HTTP fallback for macOS 13–14

**Rationale**: Apple's `Translation` framework (macOS 15+) provides on-device neural EN→FR translation that is private, free, and offline-capable after the language pack download. This is the preferred path for modern macOS. For macOS 13–14 (where the framework is unavailable or lacks a public background API), a configurable LibreTranslate HTTP endpoint serves as fallback. The fallback endpoint defaults to `libretranslate.com` and can be overridden via `TranslationService.libreTranslateURL` to point at a self-hosted instance. See `specs/001/research.md Decision 4`.

**Translation failure handling**: On any failure (network error, service unavailable, malformed response), the entry is left with `translationStatus = .pending`. A `NWPathMonitor` observer in `AppDelegate` calls `retryPendingTranslations()` automatically when connectivity is restored.

**Alternatives considered**:
- **DeepL API**: High quality, but requires an API key and sends clipboard text to a third-party server — privacy concern.
- **Google Translate API**: Same privacy concern; paid beyond free tier.
- **opus-mt bundled model**: ~300 MB binary for EN→FR — violates the 50 MB RAM constraint severely.

---

## Decision 5: Local Persistence

**Decision**: SQLite via `GRDB.swift 6.x`, single-file database at `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite`

**Rationale**: The `VocabularyEntry` model requires: unique-key deduplication on raw English text, an integer counter, a nullable translation field, a status enum, and timestamps — a relational table is the natural fit. SQLite is zero-dependency at the OS level (ships with macOS), and GRDB.swift is the de-facto lightweight Swift SQLite wrapper with Codable support, `ValueObservation` for live UI updates, and no ORM overhead. The single-file SQLite pattern survives restarts and is included in Time Machine backups. See `specs/001/research.md Decision 5`.

**Migration strategy**: GRDB `DatabaseMigrator` with named migrations (`v1`, `v2`, …). Schema version is tracked automatically. Additive changes use `ALTER TABLE ADD COLUMN`.

**Alternatives considered**:
- **JSON flat file**: Full-file rewrite on every capture becomes costly at scale; no native deduplication.
- **CoreData**: Disproportionate overhead for a single-table schema.
- **UserDefaults**: No query capability; not suited for unbounded list storage.

---

## Decision 6: Global Keyboard Shortcut

**Decision**: `KeyboardShortcuts` library (sindresorhus), wrapping Carbon `RegisterEventHotKey`, default shortcut ⌘ Shift C

**Rationale**: Registering a global hotkey requires Carbon's low-level C API or `CGEventTap`, both of which require significant boilerplate. `KeyboardShortcuts` (MIT licensed, Swift-native, actively maintained) wraps this cleanly and supports user-remapping. The default ⌘ Shift C is not a system-reserved shortcut on macOS Ventura or later. Accessibility permission is required by macOS and is documented in the onboarding flow. See `specs/001/research.md Decision 6`.

**Alternatives considered**:
- **Raw `Carbon RegisterEventHotKey`**: Works but requires Obj-C bridging and manual lifecycle management.
- **`NSEvent.addGlobalMonitorForEvents`**: Does not provide exclusive hotkey registration; misses events when the app is focused.

---

## Decision 7: Menu Bar UI

**Decision**: `NSStatusItem` + `NSPopover` for the vocabulary list panel; SwiftUI `List` inside the popover

**Rationale**: The vocabulary panel must open within 2 seconds of clicking the menu bar icon. An `NSPopover` attached to the `NSStatusItem` is the standard macOS pattern (used by 1Password mini, Fantastical, Bear) — it opens instantly, requires no separate window management, and dismisses naturally on outside click. SwiftUI inside the popover enables `ValueObservation`-driven live updates from GRDB without manual `NotificationCenter` wiring. See `specs/001/research.md Decision 7`.

**Alternatives considered**:
- **`NSMenu` dropdown**: Appropriate for simple actions, not for a scrollable data list.
- **Full `NSWindow`**: Heavier than needed; a popover is the idiomatic macOS choice.

---

## Decision 8: Connectivity Monitoring for Retry

**Decision**: `NWPathMonitor` (Apple `Network` framework) watching for path status changes

**Rationale**: `NWPathMonitor` is the modern, recommended macOS/iOS API for observing network connectivity changes. When a path transitions to `.satisfied`, `AppDelegate` triggers `translationService.retryPendingTranslations()` — translating all entries stored with `translationStatus = .pending`. This requires no polling, no timers, and has negligible CPU overhead. The monitor runs on a background `DispatchQueue`.

**Alternatives considered**:
- **Reachability (SCNetworkReachability)**: Older C API; `NWPathMonitor` is the modern replacement.
- **Timer-based retry**: Wasteful when offline; no benefit over event-driven approach.

---

## macOS Version Target

**Decision**: macOS 13 Ventura minimum

**Rationale**: macOS 13 enables SwiftUI `MenuBarExtra`, modern `NSPasteboard` APIs, and ensures `NaturalLanguage` is available. The `Translation` framework requires macOS 15; the LibreTranslate fallback path activates automatically on 13–14. Targeting macOS 12 would require additional compatibility shims without meaningful benefit.

---

## Open Edge Cases Resolved

| Edge Case | Resolution |
|-----------|-----------|
| Text > 50 chars | Length gate in `CaptureProcessorService` — silently discarded before language detection |
| Empty string or whitespace only | `ClipboardMonitorService` guards against empty strings; never forwarded |
| Mixed-language text | Classified by dominant language; if not English or confidence < 0.6 → discarded |
| Translation unavailable / offline | Entry stored as `pending`; auto-retry via `NWPathMonitor` on reconnect |
| Non-text clipboard content (image, file) | Only `NSPasteboardTypeString` content is processed; other types silently ignored |
| Same word copied faster than polling interval | Only one event emitted per `changeCount` delta; deduplication path handles repeat |
| Thousands of entries | SQLite handles trivially; SwiftUI `List` with lazy loading renders only visible rows |

---

## Summary Table

| Concern | Choice | Key Reason |
|---------|--------|-----------|
| Language / framework | Swift 5.9 + AppKit | Native macOS, minimal footprint |
| Clipboard monitoring | `NSPasteboard` polling (500 ms) | Only reliable cross-app method on macOS |
| Language detection | `NLLanguageRecognizer` (on-device) | Free, private, fast, covers EN/FR well |
| Translation | Apple `Translation` (macOS 15+) / LibreTranslate fallback | On-device, private, free |
| Persistence | SQLite via GRDB.swift 6.x | Lightweight, deduplication, `ValueObservation` |
| Global shortcut | `KeyboardShortcuts` wrapping Carbon | Clean Swift API for ⌘ Shift C |
| Menu bar UI | `NSStatusItem` + `NSPopover` + SwiftUI | Standard macOS pattern, instant open |
| Connectivity retry | `NWPathMonitor` | Event-driven, zero polling cost |
| Min macOS version | macOS 13 (Ventura) | Modern APIs without heavy shims |
