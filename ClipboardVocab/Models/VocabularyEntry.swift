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
    var triageStatus: TriageStatus
    var seenCount: Int
    var firstCapturedAt: Date
    var lastSeenAt: Date
    var isRetained: Bool

    // MARK: - SRS fields (migration v4)

    var srsState: SRSState?
    var dueDate: String?
    var interval: Double?
    var easeFactor: Double?
    var ratingCount: Int?

    // MARK: - User annotation fields (migration v5)

    var difficultyLabel: DifficultyLabel?
    var lastReviewedDate: String?

    // MARK: - Mastery flag (migration v6)

    var isMastered: Bool = false

    // MARK: - GRDB auto-increment support

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Column mapping (camelCase Swift ↔ camelCase SQL)

    enum CodingKeys: String, CodingKey {
        case id
        case englishText        = "englishText"
        case frenchTranslation  = "frenchTranslation"
        case translationStatus  = "translationStatus"
        case triageStatus       = "triageStatus"
        case seenCount          = "seenCount"
        case firstCapturedAt    = "firstCapturedAt"
        case lastSeenAt         = "lastSeenAt"
        case isRetained         = "isRetained"
        case srsState           = "srsState"
        case dueDate            = "dueDate"
        case interval           = "interval"
        case easeFactor         = "easeFactor"
        case ratingCount        = "ratingCount"
        case difficultyLabel    = "difficultyLabel"
        case lastReviewedDate   = "lastReviewedDate"
        case isMastered         = "isMastered"
    }
}

// MARK: - TranslationStatus

extension VocabularyEntry {
    enum TranslationStatus: String, Codable {
        case pending    = "pending"
        case translated = "translated"
    }
}

// MARK: - TriageStatus

extension VocabularyEntry {
    enum TriageStatus: String, Codable {
        case unreviewed = "unreviewed"
        case saved      = "saved"
        case ignored    = "ignored"
        case known      = "known"
    }
}
