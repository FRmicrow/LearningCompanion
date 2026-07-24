import AppKit
import SwiftUI

/// Owns the `NSPanel` lifecycle for the floating vocabulary sidebar.
///
/// Anchors to the right edge of the primary display. Uses `.nonactivatingPanel`
/// so that the owning application never steals key focus from the user's
/// active app. Per `contracts/vocabulary-sidebar.md` C-01 through C-07.
final class VocabularySidebarPanel {

    // MARK: - Constants

    static let width: CGFloat = 340

    // MARK: - Private state

    private let panel: NSPanel

    // MARK: - Init

    init(repository: VocabularyEntryRepository, translationService: TranslationService) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor

        let rootView = VocabularySidebarView(
            repository: repository,
            translationService: translationService,
            onEscape: { [weak self] in self?.hide() }
        )
        panel.contentViewController = NSHostingController(rootView: rootView)
    }

    // MARK: - Public interface

    /// Whether the panel is currently visible on screen.
    var isVisible: Bool {
        panel.isVisible
    }

    /// Show the panel anchored to the right edge of the primary display.
    /// No-op if already visible.
    func show() {
        guard !panel.isVisible else { return }
        if let visibleFrame = NSScreen.main?.visibleFrame {
            let frame = NSRect(
                x: visibleFrame.maxX - Self.width,
                y: visibleFrame.minY,
                width: Self.width,
                height: visibleFrame.height
            )
            panel.setFrame(frame, display: false)
        }
        panel.orderFrontRegardless()
    }

    /// Hide the panel.
    /// No-op if already hidden.
    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// Toggle visibility: show if hidden, hide if shown.
    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

}
