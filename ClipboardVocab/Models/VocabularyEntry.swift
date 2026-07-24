import Foundation
import GRDB

/// A single unique English word or phrase captured from the clipboard,
/// together with its French translation and capture metadata.
struct VocabularyEntry: Codable, FetchableRecord, MutablePersistableRecord {

    // MARK: - GRDB table name

    static let databaseTableName = "vocabulary_entries"

    // MARK: - Columns

    var id: Int64?
    var englishText: String
    var frenchTranslation: String?
    var translationStatus: TranslationStatus
    var seenCount: Int
    var firstCapturedAt: Date
    var lastSeenAt: Date
    var isRetained: Bool

    // MARK: - GRDB auto-increment support

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Column mapping (camelCase Swift ↔ snake_case SQL)

    enum CodingKeys: String, CodingKey {
        case id
        case englishText        = "englishText"
        case frenchTranslation  = "frenchTranslation"
        case translationStatus  = "translationStatus"
        case seenCount          = "seenCount"
        case firstCapturedAt    = "firstCapturedAt"
        case lastSeenAt         = "lastSeenAt"
        case isRetained         = "isRetained"
    }
}

// MARK: - TranslationStatus

extension VocabularyEntry {
    enum TranslationStatus: String, Codable {
        case pending    = "pending"
        case translated = "translated"
    }
}
