import AppKit
import SwiftUI

/// Owns the `NSStatusItem` and the `NSPopover` that hosts `VocabularyListView`.
///
/// Also surfaces a right-click menu with pause/resume and quit actions.
final class StatusItemController: NSObject, NSPopoverDelegate {

    // MARK: - Dependencies

    private let repository: VocabularyEntryRepository
    private let translationService: TranslationService
    /// Closure called when pause/resume is requested from the menu.
    var onToggleCaptureState: (() -> Void)?
    /// Closure called when quit is requested from the menu.
    var onQuit: (() -> Void)?

    // MARK: - AppKit objects

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?

    // MARK: - Init

    init(repository: VocabularyEntryRepository, translationService: TranslationService) {
        self.repository = repository
        self.translationService = translationService
        super.init()
        buildStatusItem()
        buildPopover()
    }

    // MARK: - Icon state

    /// Update the menu bar icon to reflect current capture state.
    func updateIcon(for state: CaptureState) {
        let sfName = state == .active ? "doc.on.clipboard" : "doc.on.clipboard.fill"
        let image = NSImage(systemSymbolName: sfName, accessibilityDescription: nil)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel(state == .active
            ? "ClipboardVocab — Active"
            : "ClipboardVocab — Paused")
    }

    /// Update the pause/resume label in the right-click menu.
    func updateMenu(captureState: CaptureState) {
        buildMenu(captureState: captureState)
    }

    // MARK: - Private setup

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.target = self
        updateIcon(for: .active)
    }

    private func buildPopover() {
        popover = NSPopover()
        popover.contentViewController = NSHostingController(
            rootView: VocabularyListView(
                repository: repository,
                translationService: translationService
            )
        )
        // .applicationDefined lets internal interactions (scroll, buttons) work
        // freely; the eventMonitor already handles closing on outside clicks.
        popover.behavior = .applicationDefined
        popover.delegate = self
    }

    private func buildMenu(captureState: CaptureState) {
        let menu = NSMenu()

        let toggleLabel = captureState == .active
            ? L10n.string("pause_capture_label")
            : L10n.string("resume_capture_label")
        let toggleItem = NSMenuItem(title: toggleLabel,
                                    action: #selector(toggleCapture),
                                    keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string("quit_label"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            buildMenu(captureState: .active) // updated by AppDelegate on each toggle
            statusItem.button?.performClick(nil)
        } else {
            statusItem.menu = nil
            togglePopover(sender)
        }
    }

    @objc private func toggleCapture() {
        onToggleCaptureState?()
    }

    @objc private func quit() {
        onQuit?()
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            openPopover(relativeTo: sender)
        }
    }

    private func openPopover(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Retry handled by RetryOnAppearModifier inside VocabularyListView (FR-005).
        // Install outside-click monitor
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
