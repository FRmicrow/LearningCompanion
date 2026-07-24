import AppKit
import SwiftUI

/// Owns the `NSStatusItem` and the floating `VocabularySidebarPanel`.
///
/// Surfaces a right-click menu with pause/resume and quit actions.
final class StatusItemController: NSObject {

    // MARK: - Dependencies

    private let repository: VocabularyEntryRepository
    private let translationService: TranslationService
    /// Closure called when pause/resume is requested from the menu.
    var onToggleCaptureState: (() -> Void)?
    /// Closure called when quit is requested from the menu.
    var onQuit: (() -> Void)?

    // MARK: - AppKit objects

    private var statusItem: NSStatusItem!
    private var panel: VocabularySidebarPanel!

    // MARK: - Init

    init(repository: VocabularyEntryRepository, translationService: TranslationService) {
        self.repository = repository
        self.translationService = translationService
        super.init()
        buildStatusItem()
        panel = VocabularySidebarPanel(
            repository: repository,
            translationService: translationService
        )
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

    // MARK: - Sidebar toggle (single entry-point per C-16)

    /// Show the sidebar if hidden, hide it if shown.
    /// Called by both the left-click handler and `AppDelegate` via `GlobalShortcutManager`.
    func toggleSidebar() {
        panel.toggle()
    }

    // MARK: - Private setup

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.target = self
        updateIcon(for: .active)
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
            toggleSidebar()
        }
    }

    @objc private func toggleCapture() {
        onToggleCaptureState?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
