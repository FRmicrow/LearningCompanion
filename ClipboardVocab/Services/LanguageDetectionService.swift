import AppKit
import Foundation
import NaturalLanguage
import os

/// Wraps `NLLanguageRecognizer` to detect the dominant language of a short text.
///
/// Confidence threshold is 0.6 — texts below this are treated as ambiguous and
/// discarded by the capture pipeline (research.md Decision 3).
final class LanguageDetectionService {

    // MARK: - Constants

    static let confidenceThreshold: Double = 0.6

    // MARK: - API

    struct DetectionResult {
        let language: NLLanguage
        let confidence: Double
    }

    /// Returns the dominant language and its confidence score, or `nil` if the
    /// recognizer cannot produce any hypothesis.
    func detect(text: String) -> DetectionResult? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard
            let language = recognizer.dominantLanguage,
            language != .undetermined
        else {
            AppLogger.language.debug("Langue indéterminée pour : \"\(text.prefix(20), privacy: .public)\"")
            return nil
        }

        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        AppLogger.language.debug("Détecté \(language.rawValue, privacy: .public) (confiance \(confidence, format: .fixed(precision: 2))) pour : \"\(text.prefix(20), privacy: .public)\"")
        return DetectionResult(language: language, confidence: confidence)
    }

    /// Returns `true` if the text is confidently identified as English.
    ///
    /// For short texts (≤ 2 words), `NLLanguageRecognizer` is unreliable — many valid
    /// English words (e.g. "resilience", "ephemeral") are misidentified as other European
    /// languages. For these cases, `NSSpellChecker` (English dictionary) is used as the
    /// primary signal, with `NLLanguageRecognizer` only blocking when it identifies another
    /// language with near-certain confidence (≥ 0.97).
    ///
    /// For longer texts (> 2 words), the standard NLR threshold applies.
    func isEnglish(_ text: String) -> Bool {
        let wordCount = text.split(separator: " ").count
        if wordCount <= 2 {
            return isShortTextEnglish(text)
        }
        guard let result = detect(text: text) else { return false }
        return result.language == .english && result.confidence >= Self.confidenceThreshold
    }

    // MARK: - Private

    /// Short-text English check: all words in the English dictionary, and NLR does not
    /// confidently identify another language (threshold 0.97 to avoid blocking genuine
    /// English words like "alleviate" which NLR misclassifies as Italian at ~0.92).
    private func isShortTextEnglish(_ text: String) -> Bool {
        let checker = NSSpellChecker.shared
        let words = text.split(separator: " ").map(String.init)

        // All tokens must be valid English words.
        // Reject tokens containing non-ASCII letters (accented characters like "à", "é"
        // are accepted by NSSpellChecker but are not English vocabulary words).
        let allInDictionary = words.allSatisfy { word in
            // Only allow ASCII letters, apostrophes, and hyphens (standard English spelling)
            let isAsciiWord = word.allSatisfy { $0.isASCII || $0 == "'" || $0 == "-" }
            guard isAsciiWord else { return false }
            let range = checker.checkSpelling(
                of: word,
                startingAt: 0,
                language: "en",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            return range.location == NSNotFound
        }
        guard allInDictionary else { return false }

        // Guard: if NLR is almost certain it's another language, reject.
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let lang = recognizer.dominantLanguage,
           lang != .english,
           lang != .undetermined {
            let conf = recognizer.languageHypotheses(withMaximum: 1)[lang] ?? 0
            if conf >= 0.97 { return false }
        }
        return true
    }
}
