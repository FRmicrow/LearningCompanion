import Foundation
import os

/// Delegate receiving outcomes of the capture pipeline.
protocol CaptureProcessorDelegate: AnyObject {
    /// Called when an entry is successfully stored (new insert or counter increment).
    func captureProcessor(_ processor: CaptureProcessorService,
                          didStore entry: VocabularyEntry)
    /// Called when text was silently discarded (diagnostic / testing purposes only).
    func captureProcessor(_ processor: CaptureProcessorService,
                          didDiscard text: String,
                          reason: DiscardReason)
}

/// Reasons a raw clipboard string was not persisted.
enum DiscardReason {
    case tooLong              // > 50 characters
    case noMeaningfulLanguage // numbers-only, URL, file path, etc.
    case notEnglish           // detected as non-English language
    case lowConfidence        // language detection confidence < 0.6
    case duplicate            // same text existed; counter incremented instead
}

// MARK: -

/// Applies the full capture pipeline to a raw clipboard string:
/// 1. Length gate (≤ 50 chars)
/// 2. Non-language content gate
/// 3. Language detection
/// 4. Deduplication / upsert
/// 5. Translation request
/// 6. Persistence
///
/// Per `contracts/capture-processor.md`.
/// See also: `contracts/clipboard-monitor.md` (upstream), `contracts/translation-service.md` (downstream).
final class CaptureProcessorService {

    // MARK: - Dependencies

    weak var delegate: CaptureProcessorDelegate?

    private let languageDetector: LanguageDetectionService
    private let translationService: TranslationService
    private let repository: VocabularyEntryRepository

    init(
        languageDetector: LanguageDetectionService,
        translationService: TranslationService,
        repository: VocabularyEntryRepository
    ) {
        self.languageDetector = languageDetector
        self.translationService = translationService
        self.repository = repository
    }

    // MARK: - Pipeline

    /// Process raw clipboard text asynchronously. Delegate callbacks on main thread.
    func process(text: String) async {
        AppLogger.capture.debug("Pipeline démarré pour : \"\(text.prefix(30), privacy: .public)\"")

        // 1. Length gate
        guard text.count <= 50 else {
            AppLogger.capture.debug("Rejeté (trop long : \(text.count) chars) : \"\(text.prefix(30), privacy: .public)\"")
            await notifyDiscard(text: text, reason: .tooLong)
            return
        }

        // 2. Non-language content gate
        guard hasMeaningfulLanguage(text) else {
            AppLogger.capture.debug("Rejeté (contenu non-linguistique) : \"\(text.prefix(30), privacy: .public)\"")
            await notifyDiscard(text: text, reason: .noMeaningfulLanguage)
            return
        }

        // 3. Language detection
        // Short texts (≤ 2 words) use the spell-checker-backed isEnglish() which is
        // more accurate than NLLanguageRecognizer on single vocabulary words.
        // Longer texts use detect() + threshold directly.
        let wordCount = text.split(separator: " ").count
        if wordCount <= 2 {
            guard languageDetector.isEnglish(text) else {
                AppLogger.capture.debug("Rejeté (non anglais, texte court) : \"\(text, privacy: .public)\"")
                await notifyDiscard(text: text, reason: .notEnglish)
                return
            }
        } else {
            guard let result = languageDetector.detect(text: text) else {
                AppLogger.capture.debug("Rejeté (confiance trop faible, langue indéterminée) : \"\(text.prefix(30), privacy: .public)\"")
                await notifyDiscard(text: text, reason: .lowConfidence)
                return
            }
            guard result.confidence >= LanguageDetectionService.confidenceThreshold else {
                AppLogger.capture.debug("Rejeté (confiance \(result.confidence, format: .fixed(precision: 2)) < seuil) : \"\(text.prefix(30), privacy: .public)\"")
                await notifyDiscard(text: text, reason: .lowConfidence)
                return
            }
            guard result.language == .english else {
                AppLogger.capture.debug("Rejeté (langue détectée : \(result.language.rawValue, privacy: .public)) : \"\(text.prefix(30), privacy: .public)\"")
                await notifyDiscard(text: text, reason: .notEnglish)
                return
            }
        }

        // 4. Deduplication check / upsert
        guard let entry = try? repository.upsert(englishText: text) else {
            AppLogger.capture.error("Échec de l'upsert pour : \"\(text.prefix(30), privacy: .public)\"")
            return
        }

        // If seenCount > 1 it was a duplicate — notify but don't retranslate
        if entry.seenCount > 1 {
            AppLogger.capture.debug("Doublon détecté (seenCount=\(entry.seenCount)) : \"\(text, privacy: .public)\"")
            await notifyStore(entry: entry)
            return
        }

        AppLogger.capture.info("Nouvelle entrée créée : \"\(text, privacy: .public)\"")

        // 5. Translation (new entry only)
        await translationService.translate(entry: entry)

        // 6. Re-fetch after translation so delegate receives updated state
        let updated = (try? repository.fetchAll().first { $0.id == entry.id }) ?? entry
        AppLogger.capture.debug("Pipeline terminé, statut traduction : \(updated.translationStatus.rawValue, privacy: .public)")
        await notifyStore(entry: updated)
    }

    // MARK: - Helpers

    /// Returns `false` for strings that are clearly not natural language text
    /// (pure numbers, URLs, UNIX-style paths, Windows paths, etc.).
    private func hasMeaningfulLanguage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pure numeric (integers, decimals, hex)
        let numericPattern = #"^[\d\s.,+\-*/^%$€£¥()]+$"#
        if trimmed.range(of: numericPattern, options: .regularExpression) != nil {
            return false
        }

        // URL patterns (http, https, ftp, file)
        let urlPattern = #"^(https?|ftp|file)://"#
        if trimmed.range(of: urlPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }

        // UNIX-like file paths (starts with /)
        if trimmed.hasPrefix("/") && trimmed.contains("/") {
            return false
        }

        // Windows-like paths (C:\, D:\, etc.)
        let winPath = #"^[A-Za-z]:\\"#
        if trimmed.range(of: winPath, options: .regularExpression) != nil {
            return false
        }

        return true
    }

    // MARK: - Delegate helpers (dispatched to main thread)

    @MainActor
    private func notifyStore(entry: VocabularyEntry) {
        delegate?.captureProcessor(self, didStore: entry)
    }

    @MainActor
    private func notifyDiscard(text: String, reason: DiscardReason) {
        delegate?.captureProcessor(self, didDiscard: text, reason: reason)
    }
}
