import AppKit
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Hosts a persistent, invisible SwiftUI view whose sole purpose is to keep an
/// Apple Translation session alive for the lifetime of the app (FR-001).
///
/// The popover's `VocabularyListView` is transient — it appears and disappears as
/// the user opens/closes the panel.  Tying the `TranslationSession` to that view
/// means the session is nil whenever the popover is closed, so any word captured
/// while the panel is closed cannot be translated immediately.
///
/// `TranslationSessionHost` creates a zero-size, off-screen `NSWindow` that is
/// never shown to the user.  The window hosts a SwiftUI view with a
/// `.translationTask` modifier.  Because the window (and therefore the view) is
/// never closed, the session remains valid from first launch until quit.
///
/// Usage — call `TranslationSessionHost.install(translationService:)` once from
/// `AppDelegate.applicationDidFinishLaunching(_:)`.
@MainActor
final class TranslationSessionHost {

    // MARK: - Singleton entry point

    /// Create the invisible host window and attach it to the app.
    /// Must be called once, on the main thread, after the app has finished launching.
    static func install(translationService: TranslationService) {
        // Retain for app lifetime via a static property.
        _shared = TranslationSessionHost(translationService: translationService)
    }

    // MARK: - Private state

    private static var _shared: TranslationSessionHost?
    private var hostingWindow: NSWindow?

    // MARK: - Init

    private init(translationService: TranslationService) {
        guard #available(macOS 15, *) else { return }

        let view = PersistentTranslationView(service: translationService)
        let controller = NSHostingController(rootView: view)

        // Zero-size window, completely off-screen, never shown.
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        // Make the window visible but fully transparent and out of the way.
        // NSWindow must be "shown" for SwiftUI lifecycle events (onAppear) to fire.
        window.alphaValue = 0
        window.setFrameOrigin(NSPoint(x: -10, y: -10))
        window.orderFrontRegardless()

        hostingWindow = window
    }
}

// MARK: - Persistent SwiftUI view

@available(macOS 15, *)
private struct PersistentTranslationView: View {
    let service: TranslationService

    // Initialised immediately so .translationTask never receives nil on first render.
    // Previously set in .onAppear, which may not fire on the off-screen hidden window
    // (zero-size, alphaValue=0), leaving configuration nil and the task a no-op.
    @State private var configuration: TranslationSession.Configuration? = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "fr")
    )

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                service.appleSession = session
                // Translate any entries that were captured before the session
                // was ready (covers the "captured before first open" case — FR-002).
                await service.retryPendingTranslations()
            }
    }
}
