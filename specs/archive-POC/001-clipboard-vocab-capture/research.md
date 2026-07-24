# Research: Clipboard Vocabulary Capture

**Branch**: `001-clipboard-vocab-capture` | **Date**: 2025-07-18
**Feeds into**: `plan.md`, `data-model.md`, `contracts/`

---

## Decision 1: Application Framework / Language

**Decision**: Swift + AppKit (macOS native)

**Rationale**: The spec mandates a macOS menu bar app with minimal resource footprint (<1% CPU, <50MB RAM), global keyboard shortcut registration, and deep OS integration (clipboard monitoring, system tray). Swift with AppKit is the natural fit: it ships with macOS, requires no runtime install for end users, produces small binaries, and has first-class APIs for every required capability (`NSStatusBar`, `NSPasteboard`, `NSWorkspace`, `Carbon` hotkey registration). Alternatives all carry heavier trade-offs at the resource budget.

**Alternatives considered**:
- **Electron**: Ruled out — 200–400MB RAM baseline violates SC-003 by an order of magnitude.
- **Python + rumps**: Adequate for prototyping but requires a Python runtime bundle; binary size and startup latency are worse; global hotkey registration is fragile outside native code.
- **Tauri (Rust + WebView)**: Promising resource profile, but macOS menu bar and clipboard APIs are less mature; global shortcut crate (`global-hotkey`) has known edge cases on macOS Ventura+.
- **Flutter (macOS desktop)**: Still experimental for system-tray / menu-bar use cases; no official `NSPasteboard` plugin in stable channel.

---

## Decision 2: Clipboard Monitoring Strategy

**Decision**: Polling `NSPasteboard.changeCount` on a 0.5-second timer

**Rationale**: macOS does not expose a push notification API for arbitrary clipboard changes across all applications. The standard pattern used by every major clipboard manager (Raycast, Pastebot, ClipMenu) is to poll `NSPasteboard.general.changeCount` on a short interval and compare against the last known count. A 0.5s interval is imperceptible to users while keeping CPU near zero (the check is a single integer comparison). This comfortably satisfies SC-001 (capture within 3 seconds).

**Alternatives considered**:
- **Distributed notifications (`NSPasteboard` observe)**: macOS does not post a global notification when the clipboard changes; no such API exists for arbitrary apps.
- **`IOHIDManager` keyboard intercept (Cmd+C)**: Unreliable — text can reach the clipboard through drag-and-drop, context menus, programmatic writes, or shortcuts other than Cmd+C.
- **1-second polling**: Acceptable latency but halves responsiveness for fast typists who copy-translate-paste in quick succession. 0.5s is the industry default.

---

## Decision 3: Language Detection

**Decision**: Apple's `NaturalLanguage` framework (`NLLanguageRecognizer`)

**Rationale**: `NaturalLanguage` is a first-party Apple framework available on macOS 10.14+. `NLLanguageRecognizer` runs entirely on-device with no network call, produces a dominant-language result with a confidence score, and handles short strings (single words) reasonably well. This keeps language detection instantaneous and privacy-preserving — clipboard text never leaves the device for detection. SC-006 requires >95% accuracy for clearly English/French text; Apple's model satisfies this for unambiguous single-language input.

**Handling low-confidence results**: If `NLLanguageRecognizer` returns a dominant language with confidence < 0.6 (configurable threshold), the text is silently discarded rather than misclassified. This resolves the open edge case "what happens when language cannot be detected with sufficient confidence."

**Handling mixed-language text**: Text ≤50 characters with mixed-language signals (e.g. `"c'est awesome"`) will typically be classified by the dominant language signal. Given the 50-character cap, truly mixed chunks are rare. If the dominant language result is not English, the text is ignored — consistent with FR-003/FR-005.

**Alternatives considered**:
- **langdetect / fastText (bundled model)**: Adds binary size and a dependency; no advantage over the on-device OS framework for EN/FR discrimination.
- **Remote language detection API**: Adds latency, network dependency, and privacy risk for a task the OS can do locally.

---

## Decision 4: Translation Service

**Decision**: Apple's `Translation` framework (macOS 15+) with a LibreTranslate fallback option for older macOS

**Rationale**: Apple's `Translation` framework (introduced in macOS 15 / iOS 17.4) provides on-device neural translation that is privacy-preserving, free, and offline-capable after the language pack is downloaded. For EN→FR it uses the same model as the Translate app. This satisfies SC-001 (translation within 3 seconds), requires no API key, and costs nothing. For macOS 14 and earlier (where the framework is unavailable), a configurable LibreTranslate endpoint (self-hosted or public) can serve as fallback.

**FR-015/FR-016/FR-017 (translation pending + retry)**: When the Translation framework reports an error (model not downloaded, macOS < 15 with no LibreTranslate configured), the entry is stored with `translationStatus = .pending`. A background task retries pending entries when the app becomes active or a manual retry is triggered.

**Alternatives considered**:
- **DeepL API**: High quality, but requires an API key, rate limits, and sends text to a third-party server — privacy concern given the clipboard captures sensitive-adjacent content.
- **Google Translate API**: Same privacy concern; paid beyond free tier.
- **`MLKit` Translation (Google, on-device)**: Not available on macOS; iOS-only.
- **`opus-mt` bundled model**: Open-source, offline, but model binary is ~300MB for EN→FR — violates SC-003 (50MB RAM budget) severely.

---

## Decision 5: Local Persistence

**Decision**: SQLite via `GRDB.swift`

**Rationale**: The `VocabularyEntry` data model requires: unique-key deduplication on raw English text, an integer counter, a nullable translation field, a status enum, and a timestamp — a relational table is the natural fit. SQLite is zero-dependency at the OS level (ships with macOS), and `GRDB.swift` is the de-facto lightweight Swift SQLite wrapper with Codable support and no ORM overhead. A single `vocabulary.sqlite` file in the app's Application Support directory satisfies SC-005 (data survives restarts/reboots) and the single-user local storage assumption.

**Why not flat file (JSON/plist)**: With potentially thousands of entries, full-file rewrite on every capture becomes increasingly costly. SQLite's atomic `INSERT OR REPLACE` with a unique constraint on `englishText` handles deduplication natively at the storage layer.

**Why not CoreData**: CoreData is well-suited to document-based or multi-entity apps with complex relationships. For a single table with ~5 columns it is significant overhead (schema migration, managed object context threading, NSPersistentContainer setup). GRDB is leaner and easier to test.

**Alternatives considered**:
- **UserDefaults**: Not appropriate for unbounded list storage; no query capability.
- **Realm**: Adds a heavy dependency; GRDB covers all needs with lighter footprint.

---

## Decision 6: Global Keyboard Shortcut Registration

**Decision**: `MASShortcut` library (or `KeyboardShortcuts` by sindresorhus)

**Rationale**: Registering a global hotkey (Command+Shift+C) requires Carbon's `RegisterEventHotKey` or the newer `CGEventTap` API. Both are low-level C APIs with boilerplate. `KeyboardShortcuts` (MIT, Swift-native, actively maintained) wraps this cleanly with a SwiftUI/AppKit binding, supports user-remapping, and handles the permission prompt for accessibility access if needed. The default shortcut (Command+Shift+C) must be checked against common system shortcuts at implementation time; the spec designates it as the default but allows remapping.

**Alternatives considered**:
- **Raw `Carbon RegisterEventHotKey`**: Works but requires Obj-C bridging and manual lifecycle management.
- **`NSEvent.addGlobalMonitorForEvents`**: Only receives key-down events when another app is focused; does not provide exclusive hotkey registration.

---

## Decision 7: Menu Bar UI

**Decision**: `NSStatusItem` + `NSPopover` for the vocabulary list panel

**Rationale**: The spec requires the vocabulary list to be accessible within 2 seconds of clicking the menu bar icon (SC-004). An `NSPopover` attached to the `NSStatusItem` is the standard macOS pattern for menu bar apps (used by 1Password mini, Fantastical, Bear, etc.). It opens instantly, avoids a full window, and closes naturally when the user clicks elsewhere. The vocabulary list inside the popover can be an `NSTableView` or `List` (SwiftUI) scrollable view.

**Alternatives considered**:
- **`NSMenu` dropdown**: Appropriate for simple action menus, not for a scrollable data list.
- **Full `NSWindow`**: Heavier than needed; a popover is the idiomatic choice.
- **SwiftUI `MenuBarExtra`** (macOS 13+): Cleaner API but limited to macOS 13+; using `NSStatusItem` directly maintains macOS 12 compatibility if desired.

---

## Open Edge Cases Resolved

| Edge Case | Resolution |
|-----------|-----------|
| Very long text (>50 chars) | Silently skipped before language detection — FR-014 |
| Mixed-language text | Classified by dominant language; if not English → ignored |
| Low-confidence language detection | Confidence threshold 0.6; below threshold → silently discarded |
| Translation unavailable / offline | Stored as `pending`; auto-retry on reconnect; manual retry available — FR-015/016/017 |
| Non-text clipboard content (image, file) | `NSPasteboard` type check: only `NSPasteboardTypeString` content is processed; all other types silently ignored |
| Thousands of entries | SQLite handles this trivially; `NSTableView` with virtual scrolling renders only visible rows |
| Clipboard contains a file path / URL | Caught by FR-006 (no meaningful natural language) + length/language checks |

---

## macOS Version Target

**Decision**: macOS 13 (Ventura) minimum

**Rationale**: macOS 13 enables `MenuBarExtra` in SwiftUI and ensures `NaturalLanguage` and a modern `NSPasteboard` API are available. The `Translation` framework requires macOS 15; for macOS 13–14 the LibreTranslate fallback path applies. Targeting macOS 12 would require additional compatibility shims without meaningful benefit.

---

## Summary Table

| Concern | Choice | Key Reason |
|---------|--------|-----------|
| Language / framework | Swift + AppKit | Native macOS, minimal footprint |
| Clipboard monitoring | `NSPasteboard` polling (0.5s) | Only reliable cross-app method on macOS |
| Language detection | `NLLanguageRecognizer` (on-device) | Free, private, fast, covers EN/FR well |
| Translation | Apple `Translation` framework (macOS 15+) / LibreTranslate fallback | On-device, private, free |
| Persistence | SQLite via GRDB.swift | Lightweight, handles deduplication natively |
| Global shortcut | `KeyboardShortcuts` library | Clean Swift API for Command+Shift+C |
| Menu bar UI | `NSStatusItem` + `NSPopover` | Standard macOS pattern, instant open |
| Min macOS version | macOS 13 (Ventura) | Modern APIs without heavy shims |
