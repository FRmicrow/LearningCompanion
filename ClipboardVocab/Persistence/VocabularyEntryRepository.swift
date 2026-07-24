import Foundation
import GRDB
import os

/// CRUD + upsert operations for `VocabularyEntry` rows.
///
/// All methods are synchronous and must be called from a background queue or
/// wrapped with `Task` / `DispatchQueue.global()` where appropriate.
final class VocabularyEntryRepository {

    // MARK: - Dependencies

    internal let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Upsert (insert new or increment seen counter)

    /// Insert a new entry with `seenCount = 1` and `translationStatus = .pending`,
    /// or increment `seenCount` and update `lastSeenAt` if the English text already exists.
    ///
    /// - Returns: The stored (new or updated) entry.
    @discardableResult
    func upsert(englishText: String) throws -> VocabularyEntry {
        try dbQueue.write { db in
            if var existing = try VocabularyEntry
                .filter(Column("englishText") == englishText)
                .fetchOne(db)
            {
                existing.seenCount += 1
                existing.lastSeenAt = Date()
                try existing.update(db)
                AppLogger.persistence.debug("Upsert (doublon, seenCount=\(existing.seenCount)) : \"\(englishText, privacy: .public)\"")
                return existing
            } else {
                let now = Date()
                var entry = VocabularyEntry(
                    id: nil,
                    englishText: englishText,
                    frenchTranslation: nil,
                    translationStatus: .pending,
                    seenCount: 1,
                    firstCapturedAt: now,
                    lastSeenAt: now,
                    isRetained: false
                )
                try entry.insert(db)
                AppLogger.persistence.info("Nouvelle entrée insérée : \"\(englishText, privacy: .public)\"")
                return entry
            }
        }
    }

    // MARK: - Update

    /// Persist changes to an existing entry (e.g. after translation succeeds).
    func update(entry: VocabularyEntry) throws {
        try dbQueue.write { db in
            try entry.update(db)
        }
        AppLogger.persistence.debug("Entrée mise à jour (id=\(entry.id ?? -1), statut=\(entry.translationStatus.rawValue, privacy: .public))")
    }

    // MARK: - Delete

    /// Hard-delete an entry by primary key. Re-capturing the same text after
    /// deletion will create a fresh row with `seenCount = 1`.
    func delete(id: Int64) throws {
        try dbQueue.write { db in
            _ = try VocabularyEntry.deleteOne(db, key: id)
        }
        AppLogger.persistence.info("Entrée supprimée (id=\(id))")
    }

    // MARK: - Retained state

    /// Set the `isRetained` flag for an entry by primary key.
    func markRetained(id: Int64, _ retained: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE vocabulary_entries SET isRetained = ? WHERE id = ?",
                arguments: [retained, id]
            )
        }
        AppLogger.persistence.info("isRetained=\(retained) pour id=\(id)")
    }

    // MARK: - Fetch

    /// All entries ordered most-recently-captured first (FR-010).
    func fetchAll() throws -> [VocabularyEntry] {
        try dbQueue.read { db in
            try VocabularyEntry
                .order(Column("firstCapturedAt").desc)
                .fetchAll(db)
        }
    }

    /// Entries whose `translationStatus` is `.pending` (used by retry queue).
    func fetchPending() throws -> [VocabularyEntry] {
        try dbQueue.read { db in
            try VocabularyEntry
                .filter(Column("translationStatus") == VocabularyEntry.TranslationStatus.pending.rawValue)
                .fetchAll(db)
        }
    }

    /// Entries older than `cutoff` that have not been marked as retained.
    /// Used to populate the "Old Unretained Words" panel section (FR-007).
    func fetchOldUnretained(before cutoff: Date) throws -> [VocabularyEntry] {
        try dbQueue.read { db in
            try VocabularyEntry
                .filter(Column("isRetained") == false)
                .filter(Column("firstCapturedAt") < cutoff)
                .order(Column("firstCapturedAt").desc)
                .fetchAll(db)
        }
    }
}
