# Service Contract: ClipboardMonitor

**Component**: `ClipboardMonitorService`
**Direction**: Internal — called by the app's background timer
**Source**: `research.md` Decision 2 (polling strategy)

---

## Responsibilities

Polls `NSPasteboard.general` every 0.5 seconds. On each tick, compares the current `changeCount` to the last observed value. If changed, reads the new string content and emits it for downstream processing.

## Interface

```swift
protocol ClipboardMonitorDelegate: AnyObject {
    /// Called on the main thread when new plain-text clipboard content is detected.
    /// - Parameter text: Raw string from the clipboard. May be any language, length, or content.
    func clipboardMonitor(_ monitor: ClipboardMonitorService, didCapture text: String)
}

final class ClipboardMonitorService {
    weak var delegate: ClipboardMonitorDelegate?

    /// Start polling. No-op if already running.
    func start()

    /// Pause polling. Clipboard events are silently dropped until `resume()` is called.
    /// Satisfies FR-018/FR-019.
    func pause()

    /// Resume polling after a pause.
    func resume()

    /// Stop polling entirely and release timer resources.
    func stop()

    /// Current capture state.
    var captureState: CaptureState { get }
}

enum CaptureState {
    case active
    case paused
}
```

## Behaviour Contract

| Condition | Behaviour |
|-----------|-----------|
| `captureState == .paused` | Timer still fires but `didCapture` is NOT called; no side effects |
| Clipboard has non-text content (image, file) | Only `NSPasteboardTypeString` is read; non-text types are silently ignored |
| `changeCount` unchanged since last tick | No delegate call |
| `changeCount` changed, content is empty string | No delegate call |
| Multiple rapid copies between ticks | Only the latest clipboard value is emitted |

## Timing

- Polling interval: **500ms**
- Thread: `DispatchQueue` background timer; delegate callback dispatched to **main thread**
