import Foundation
import os
#if canImport(Translation)
import Translation
#endif

/// Translates English text to French.
///
/// Strategy (research.md Decision 4):
/// - macOS 15+: Apple `Translation` framework (on-device, private), session
///   injected from the SwiftUI view layer via `appleSession`.
/// - macOS 13–14 (or when `appleSession` is nil): LibreTranslate HTTP POST fallback.
///
/// On any failure, throws `TranslationError.unavailable` so the caller can
/// store the entry as `.pending` and retry later.
///
/// Per `contracts/translation-service.md`.
final class TranslationService {

    // MARK: - Errors

    enum TranslationError: Error {
        case unavailable
        case networkError(Error)
        case decodingError
    }

    // MARK: - Configuration

    /// LibreTranslate endpoint used as fallback when the Apple session is unavailable.
    /// Defaults to the public instance; can be overridden for self-hosted setups.
    var libreTranslateURL: URL = URL(string: "https://libretranslate.com/translate")!

    /// Optional API key sent as `"api_key"` in the request body.
    /// Required by the public libretranslate.com instance (free key at portal.libretranslate.com).
    /// Leave empty when using a self-hosted instance that doesn't require authentication.
    var apiKey: String = ""

    // MARK: - Apple Translation session (macOS 15+)

    /// Set by the SwiftUI view layer (VocabularyListView) once `.translationTask` provides a
    /// live `TranslationSession`. When non-nil, all translations use the on-device model.
    /// Falls back to LibreTranslate when nil (macOS < 15 or model not yet available).
    @available(macOS 15, *)
    var appleSession: TranslationSession? {
        get { _appleSession as? TranslationSession }
        set { _appleSession = newValue }
    }
    private var _appleSession: AnyObject?
    private var retryInProgress = false

    // MARK: - Repository (injected for retry)

    private let repository: VocabularyEntryRepository

    init(repository: VocabularyEntryRepository) {
        self.repository = repository
    }

    // MARK: - Public API

    // MARK: Offline behaviour
    //
    // `translate(entry:)` NEVER throws. On any failure (network error, non-2xx HTTP,
    // malformed JSON), the entry is left with `translationStatus = .pending`.
    // A `NWPathMonitor` observer in AppDelegate calls `retryPendingTranslations()`
    // automatically when connectivity is restored, translating all pending entries.
    // Per `contracts/translation-service.md`.

    /// Translate a single `VocabularyEntry`.
    /// On success, updates `frenchTranslation` and `translationStatus` in the DB.
    /// On failure, leaves the entry as `.pending`. Never throws.
    func translate(entry: VocabularyEntry) async {
        AppLogger.translation.debug("Traduction demandée pour : \"\(entry.englishText, privacy: .public)\"")
        do {
            let translated = try await translateText(entry.englishText)
            var updated = entry
            updated.frenchTranslation = translated
            updated.translationStatus = .translated
            try repository.update(entry: updated)
            AppLogger.translation.info("Traduit : \"\(entry.englishText, privacy: .public)\" → \"\(translated, privacy: .public)\"")
        } catch TranslationError.unavailable {
            // Service not ready (e.g. Apple model not yet downloaded) — will be retried automatically.
            AppLogger.translation.debug("Service indisponible pour \"\(entry.englishText, privacy: .public)\" — sera retenté automatiquement")
        } catch {
            // Unexpected failure (network error, decoding error) — left as pending for background retry.
            AppLogger.translation.warning("Erreur inattendue pour \"\(entry.englishText, privacy: .public)\" : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Retry all entries currently marked `.pending`.
    /// If a retry pass is already in flight, this call is a no-op and returns immediately.
    func retryPendingTranslations() async {
        guard !retryInProgress else {
            AppLogger.translation.debug("Retry déjà en cours, ignoré")
            return
        }
        retryInProgress = true
        defer { retryInProgress = false }
        guard let pending = try? repository.fetchPending() else { return }
        guard !pending.isEmpty else {
            AppLogger.translation.debug("Aucune entrée en attente à retraiter")
            return
        }
        AppLogger.translation.info("Retry de \(pending.count) entrée(s) en attente")
        for entry in pending {
            await translate(entry: entry)
        }
    }

    /// Re-translate every `.pending` entry in `entries`.
    ///
    /// - Returns: The count of entries that were successfully translated.
    /// - Throws: `TranslationError.unavailable` if the translation service is wholly
    ///   unreachable and no entry succeeded (i.e. successCount == 0 and at least one
    ///   translation was attempted).
    @discardableResult
    func retryGroup(entries: [VocabularyEntry]) async throws -> Int {
        // Only retry entries that still need a translation — skip already-translated ones.
        let pending = entries.filter { $0.translationStatus == .pending }
        guard !pending.isEmpty else { return 0 }

        var successCount = 0
        var lastError: Error?
        for entry in pending {
            do {
                let translated = try await translateText(entry.englishText)
                var updated = entry
                updated.frenchTranslation = translated
                updated.translationStatus = .translated
                try repository.update(entry: updated)
                successCount += 1
            } catch {
                lastError = error
            }
        }
        if successCount == 0, let error = lastError {
            throw error
        }
        return successCount
    }

    // MARK: - Internal translation

    private func translateText(_ text: String) async throws -> String {
        if #available(macOS 15, *), _appleSession != nil {
            AppLogger.translation.debug("Stratégie : Apple Translation Framework (macOS 15+)")
            // translateWithAppleFramework nils appleSession on failure and rethrows —
            // fall through to LibreTranslate immediately rather than leaving pending.
            if let result = try? await translateWithAppleFramework(text) {
                return result
            }
            AppLogger.translation.debug("Bascule sur LibreTranslate HTTP après échec Apple")
        }
        AppLogger.translation.debug("Stratégie : LibreTranslate HTTP")
        return try await translateWithLibreTranslate(text)
    }

    @available(macOS 15, *)
    private func translateWithAppleFramework(_ text: String) async throws -> String {
        guard let session = appleSession else {
            // Session not yet available — fall through to LibreTranslate.
            throw TranslationError.unavailable
        }
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            // Session is broken (model not ready, invalidated, etc.).
            // Nil it so subsequent calls fall through to LibreTranslate,
            // and PersistentTranslationView will supply a fresh session via .translationTask.
            AppLogger.translation.warning("Session Apple invalide, bascule sur LibreTranslate : \(error.localizedDescription, privacy: .public)")
            appleSession = nil
            throw error
        }
    }

    private func translateWithLibreTranslate(_ text: String) async throws -> String {
        var request = URLRequest(url: libreTranslateURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "q": text,
            "source": "en",
            "target": "fr",
            "format": "text"
        ]
        if !apiKey.isEmpty {
            body["api_key"] = apiKey
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            AppLogger.translation.error("LibreTranslate HTTP \(statusCode) pour : \"\(text.prefix(20), privacy: .public)\"")
            throw TranslationError.unavailable
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let translated = json["translatedText"] as? String
        else {
            throw TranslationError.decodingError
        }

        return translated
    }
}
