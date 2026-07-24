import AppKit
import Network
import os

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, ClipboardMonitorDelegate {

    // MARK: - Core services

    private var database: Database!
    private var repository: VocabularyEntryRepository!
    private var translationService: TranslationService!
    private var clipboardMonitor: ClipboardMonitorService!
    private var captureProcessor: CaptureProcessorService!

    // MARK: - UI

    private var statusItemController: StatusItemController!

    // MARK: - Connectivity

    private var pathMonitor: NWPathMonitor?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.app.info("Application démarrée")

        // 1. Database
        database = Database.shared
        repository = VocabularyEntryRepository(dbQueue: database.dbQueue)

        // 2. Services
        translationService = TranslationService(repository: repository)
        // Self-hosted LibreTranslate running on Docker (port 5001 — no API key required).
        translationService.libreTranslateURL = URL(string: "http://localhost:5001/translate")!
        AppLogger.app.info("LibreTranslate configuré sur \("http://localhost:5001/translate", privacy: .public)")
        let languageDetector = LanguageDetectionService()
        captureProcessor = CaptureProcessorService(
            languageDetector: languageDetector,
            translationService: translationService,
            repository: repository
        )

        // 3. Clipboard monitor — always starts active (FR-020)
        clipboardMonitor = ClipboardMonitorService()
        clipboardMonitor.delegate = self
        clipboardMonitor.start()

        // 4. Menu bar UI
        statusItemController = StatusItemController(
            repository: repository,
            translationService: translationService
        )
        statusItemController.onToggleCaptureState = { [weak self] in
            self?.toggleCaptureState()
        }
        statusItemController.onQuit = {
            NSApplication.shared.terminate(nil)
        }

        // 5. Apple Translation session host — keeps the session alive independently
        //    of the sidebar lifecycle so that words captured before the panel is
        //    opened are translated immediately (FR-001, FR-002).
        TranslationSessionHost.install(translationService: translationService)

        // 6. Global keyboard shortcut: Command+Shift+C — toggles the sidebar (C-18)
        GlobalShortcutManager.shared.register { [weak self] in
            self?.statusItemController.toggleSidebar()
        }

        // 6. Connectivity observer for pending translation retry
        startConnectivityMonitor()
        AppLogger.app.info("Initialisation terminée")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.app.info("Application en cours d'arrêt")
        clipboardMonitor.stop()
        GlobalShortcutManager.shared.unregister()
        pathMonitor?.cancel()
    }

    // MARK: - Capture state toggle (T030)

    func toggleCaptureState() {
        switch clipboardMonitor.captureState {
        case .active:
            clipboardMonitor.pause()
        case .paused:
            clipboardMonitor.resume()
        }
        let newState = clipboardMonitor.captureState
        AppLogger.app.info("État de capture basculé → \(newState == .active ? "actif" : "en pause", privacy: .public)")
        statusItemController.updateIcon(for: newState)
        statusItemController.updateMenu(captureState: newState)
    }

    // MARK: - ClipboardMonitorDelegate

    func clipboardMonitor(_ monitor: ClipboardMonitorService, didCapture text: String) {
        Task {
            await captureProcessor.process(text: text)
        }
    }

    // MARK: - Connectivity observer (T035/T036)

    private func startConnectivityMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            AppLogger.app.info("Connectivité rétablie — déclenchement du retry de traduction")
            Task {
                await self?.translationService.retryPendingTranslations()
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        pathMonitor = monitor
        AppLogger.app.debug("Surveillance réseau démarrée")
    }
}
