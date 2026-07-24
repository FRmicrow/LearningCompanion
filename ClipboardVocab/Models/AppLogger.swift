import os

/// Centralise les instances `Logger` de l'application.
///
/// Chaque composant dispose de sa propre catégorie, ce qui permet de filtrer
/// les logs dans Console.app ou via `log stream --predicate`.
///
/// Usage :
/// ```swift
/// AppLogger.clipboard.debug("Texte capturé : \(text, privacy: .public)")
/// AppLogger.translation.error("Échec HTTP \(statusCode)")
/// ```
enum AppLogger {

    private static let subsystem = "com.clipboardvocab"

    /// Surveillance du presse-papiers (`ClipboardMonitorService`)
    static let clipboard    = Logger(subsystem: subsystem, category: "clipboard")

    /// Pipeline de capture (`CaptureProcessorService`)
    static let capture      = Logger(subsystem: subsystem, category: "capture")

    /// Détection de langue (`LanguageDetectionService`)
    static let language     = Logger(subsystem: subsystem, category: "language")

    /// Service de traduction (`TranslationService`)
    static let translation  = Logger(subsystem: subsystem, category: "translation")

    /// Accès base de données (`VocabularyEntryRepository`)
    static let persistence  = Logger(subsystem: subsystem, category: "persistence")

    /// Raccourci clavier global (`GlobalShortcutManager`)
    static let shortcut     = Logger(subsystem: subsystem, category: "shortcut")

    /// Cycle de vie de l'application (`AppDelegate`, `Database`)
    static let app          = Logger(subsystem: subsystem, category: "app")
}
