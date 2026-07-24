import AppKit
import Foundation
import os

/// Delegate receiving new clipboard captures.
protocol ClipboardMonitorDelegate: AnyObject {
    /// Called on the main thread when new plain-text clipboard content is detected.
    /// - Parameter text: Raw string from the clipboard. May be any language, length, or content.
    func clipboardMonitor(_ monitor: ClipboardMonitorService, didCapture text: String)
}

/// Polls `NSPasteboard.general` every 500 ms and emits new plain-text content
/// to its delegate. Supports pause/resume without destroying the underlying timer.
///
/// Per `contracts/clipboard-monitor.md`.
final class ClipboardMonitorService {

    // MARK: - Public interface

    weak var delegate: ClipboardMonitorDelegate?

    /// Current capture state. Always `.active` on init (FR-011).
    private(set) var captureState: CaptureState = .active

    // MARK: - Private state

    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let queue = DispatchQueue(label: "com.clipboardvocab.monitor", qos: .background)

    // MARK: - Lifecycle

    /// Start polling. No-op if already running.
    func start() {
        guard timer == nil else { return }

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(500))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        source.resume()
        timer = source
        AppLogger.clipboard.info("Surveillance du presse-papiers démarrée (intervalle 500 ms)")
    }

    /// Pause polling. Timer keeps firing but `didCapture` is NOT called.
    ///
    /// **Invariant**: The underlying `DispatchSourceTimer` is NOT cancelled on pause —
    /// only the delegate call is suppressed. This avoids timer destruction/recreation
    /// overhead and ensures resume is instantaneous.
    /// Per `contracts/clipboard-monitor.md` and FR-011.
    func pause() {
        captureState = .paused
        AppLogger.clipboard.info("Capture mise en pause")
    }

    /// Resume after a pause.
    ///
    /// **Invariant**: `captureState` is always `.active` on `init` and after every app
    /// launch — pause state is never persisted across restarts (FR-011).
    func resume() {
        captureState = .active
        AppLogger.clipboard.info("Capture reprise")
    }

    /// Stop polling and release timer resources.
    func stop() {
        timer?.cancel()
        timer = nil
        AppLogger.clipboard.info("Surveillance du presse-papiers arrêtée")
    }

    // MARK: - Timer tick (runs on background queue)

    private func tick() {
        let pasteboard = NSPasteboard.general
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // Paused: discard silently
        guard captureState == .active else {
            AppLogger.clipboard.debug("Changement ignoré (capture en pause)")
            return
        }

        // Only process plain-text content
        guard
            let text = pasteboard.string(forType: .string),
            !text.isEmpty
        else { return }

        AppLogger.clipboard.debug("Texte capturé : \(text.prefix(30), privacy: .public)…")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.clipboardMonitor(self, didCapture: text)
        }
    }
}
