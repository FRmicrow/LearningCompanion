# Service Contract: ClipboardMonitor

**Component**: `ClipboardMonitorService`
**Direction**: Internal — called by the app's background timer
**Source**: `research.md` Decision 2 (polling strategy)

---

## Responsibilities

Polls `NSPasteboard.general` every 500 ms using a `DispatchSourceTimer` on a dedicated background queue. On each tick, compares the current `changeCount` to the last observed value. If changed and the service is not paused, reads the plain-text string content and emits it to the delegate on the **main thread**.

Does **not** filter, validate, or translate content — that responsibility belongs to `CaptureProcessorService`.

---

## Interface

```swift
protocol ClipboardMonitorDelegate: AnyObject {
    /// Called on the main thread when new plain-text clipboard content is detected.
    /// - Parameter text: Raw string from the clipboard. May be any language, length, or content.
    func clipboardMonitor(_ monitor: ClipboardMonitorService, didCapture text: String)
}

final class ClipboardMonitorService {
    weak var delegate: ClipboardMonitorDelegate?

    /// Current capture state. Always `.active` on init (FR-011).
    private(set) var captureState: CaptureState

    /// Start polling. No-op if already running.
    func start()

    /// Pause polling. Timer still fires but `didCapture` is NOT called.
    func pause()

    /// Resume polling after a pause.
    func resume()

    /// Stop polling entirely and release timer resources.
    func stop()
}

enum CaptureState {
    case active
    case paused
}
```

---

## Behaviour Contract

| Condition | Behaviour |
|-----------|-----------|
| `captureState == .paused` | Timer fires but `didCapture` is **not** called; no side effects |
| Clipboard has non-text content (image, file) | Only `NSPasteboardTypeString` is read; other types silently ignored |
| `changeCount` unchanged since last tick | No delegate call |
| `changeCount` changed, content is empty string | No delegate call |
| Multiple rapid copies between ticks | Only the latest clipboard value is emitted (one event per `changeCount` delta) |
| `start()` called when already running | No-op; timer is not recreated |

---

## Threading

| Operation | Thread |
|-----------|--------|
| Timer tick / `changeCount` check | Background `DispatchQueue` (`com.clipboardvocab.monitor`) |
| `didCapture` delegate callback | Main thread (`DispatchQueue.main.async`) |
| `pause()` / `resume()` / `stop()` | May be called from any thread |

---

## Timing

- **Polling interval**: 500 ms
- **Maximum capture latency from copy to delegate call**: ≤ 500 ms + main-thread scheduling overhead (typical: < 10 ms)
- **SC-001 contribution**: ≤ 500 ms of the total ≤ 3 s budget
