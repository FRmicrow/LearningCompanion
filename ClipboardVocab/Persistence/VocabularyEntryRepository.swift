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
                    triageStatus: .unreviewed,
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

    // MARK: - Inbox triage (Epic 2)

    /// All entries with `triageStatus == 'unreviewed'`, ordered most-recently-captured first.
    func fetchInbox() throws -> [VocabularyEntry] {
        try dbQueue.read { db in
            try VocabularyEntry
                .filter(Column("triageStatus") == VocabularyEntry.TriageStatus.unreviewed.rawValue)
                .order(Column("firstCapturedAt").desc)
                .fetchAll(db)
        }
    }

    /// Count of entries with `triageStatus == 'unreviewed'`. Used for Inbox badge.
    func fetchInboxCount() throws -> Int {
        try dbQueue.read { db in
            try VocabularyEntry
                .filter(Column("triageStatus") == VocabularyEntry.TriageStatus.unreviewed.rawValue)
                .fetchCount(db)
        }
    }

    /// Mark an entry as saved, atomically seeding SRS defaults (C-38, C-39).
    ///
    /// Sets `triageStatus = 'saved'`, `srsState = 'new'`, `dueDate = today`,
    /// `interval = 1.0`, `easeFactor = 2.5`, `ratingCount = 0` in a single UPDATE.
    func markSaved(id: Int64) throws {
        let today = todayString()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE vocabulary_entries
                    SET triageStatus = 'saved',
                        srsState     = 'new',
                        dueDate      = ?,
                        interval     = 1.0,
                        easeFactor   = 2.5,
                        ratingCount  = 0
                    WHERE id = ?
                    """,
                arguments: [today, id]
            )
        }
        AppLogger.persistence.info("markSaved id=\(id), dueDate=\(today)")
    }

    /// Mark an entry as ignored (removed from Inbox, not in learning pipeline).
    func markIgnored(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE vocabulary_entries SET triageStatus = 'ignored' WHERE id = ?",
                arguments: [id]
            )
        }
        AppLogger.persistence.info("markIgnored id=\(id)")
    }

    /// Mark an entry as known (saved with "already known" marker).
    func markKnown(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE vocabulary_entries SET triageStatus = 'known' WHERE id = ?",
                arguments: [id]
            )
        }
        AppLogger.persistence.info("markKnown id=\(id)")
    }

    // MARK: - SRS queue (Epic 3)

    /// All entries with `triageStatus == 'saved'` and `dueDate ≤ today`,
    /// ordered by `dueDate` ascending (oldest/most-overdue first).
    ///
    /// `todayString` is computed at call time — never cached across midnight.
    func fetchDueEntries() throws -> [VocabularyEntry] {
        let today = todayString()
        return try dbQueue.read { db in
            try VocabularyEntry
                .filter(Column("triageStatus") == VocabularyEntry.TriageStatus.saved.rawValue)
                .filter(Column("dueDate") <= today)
                .order(Column("dueDate").asc)
                .fetchAll(db)
        }
    }

    /// Count of entries in the daily review queue.
    ///
    /// **ValueObservation pattern** (T022) — for `DailyProgressBar` (Epic 1) and session header (Epic 4):
    ///
    /// ```swift
    /// let obs = ValueObservation.tracking { db in
    ///     let today = todayString() // computed inside closure at observation time
    ///     return try VocabularyEntry
    ///         .filter(Column("triageStatus") == "saved")
    ///         .filter(Column("dueDate") <= today)
    ///         .fetchCount(db)
    /// }
    /// countTask = Task { @MainActor in
    ///     for try await count in obs.values(in: repository.dbQueue) {
    ///         self.dueCount = count
    ///     }
    /// }
    /// ```
    ///
    /// The observation fires automatically after every `applyRating` write (C-37).
    /// No `NotificationCenter` or manual refresh needed.
    func fetchDueCount() throws -> Int {
        let today = todayString()
        return try dbQueue.read { db in
            try VocabularyEntry
                .filter(Column("triageStatus") == VocabularyEntry.TriageStatus.saved.rawValue)
                .filter(Column("dueDate") <= today)
                .fetchCount(db)
        }
    }

    /// Writes all five SRS fields in a single atomic transaction.
    ///
    /// - Throws on DB error. Callers must catch and apply re-queue behaviour.
    ///   Do NOT call with `try?` — silent failure breaks the SRS pipeline.
    /// - Does NOT touch `triageStatus`, `englishText`, `frenchTranslation`, or any other column.
    func applyRating(id: Int64, update: SRSUpdate) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE vocabulary_entries
                    SET srsState    = ?,
                        dueDate     = ?,
                        interval    = ?,
                        easeFactor  = ?,
                        ratingCount = ?
                    WHERE id = ?
                    """,
                arguments: [
                    update.srsState.rawValue,
                    update.dueDate,
                    update.interval,
                    update.easeFactor,
                    update.ratingCount,
                    id
                ]
            )
        }
    }

    // MARK: - Private helpers

    /// Today's date as a `YYYY-MM-DD` string in the device's local calendar.
    /// Computed at call time — never hardcoded or cached across midnight.
    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar   = Calendar.current
        return formatter.string(from: Date())
    }
}
