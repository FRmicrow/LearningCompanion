import Testing
import Foundation
import GRDB
@testable import ClipboardVocab

/// Verifies that migration v4 runs cleanly and produces the correct schema.
///
/// Tests run against in-memory databases. T032 (persistence across restart) uses
/// a temp file path — see VocabularyEntryRepositoryTests for that test.
@Suite("DatabaseMigrationV4Tests")
struct DatabaseMigrationV4Tests {

    // MARK: - Helpers

    /// Helper to insert a raw row at the v1/v2/v3 schema level using raw SQL,
    /// bypassing the current Swift model (which includes v4 fields).
    private func insertLegacyRow(db: DatabaseQueue, englishText: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO vocabulary_entries
                        (englishText, frenchTranslation, translationStatus,
                         seenCount, firstCapturedAt, lastSeenAt, isRetained, triageStatus)
                    VALUES (?, NULL, 'pending', 1,
                            datetime('now'), datetime('now'), 0, 'unreviewed')
                    """,
                arguments: [englishText]
            )
        }
    }

    // MARK: - v4 migration structural checks

    @Test("v4 migration runs without error on a fresh in-memory DB")
    func testV4MigrationRunsWithoutError() throws {
        // Database(path:":memory:") triggers all migrations including v4
        #expect(throws: Never.self) {
            _ = try Database(path: ":memory:")
        }
    }

    @Test("vocabulary_entries table has all five SRS columns after v4")
    func testAllFiveSRSColumnsExist() throws {
        let db = try Database(path: ":memory:")
        let columnNames = try db.dbQueue.read { db in
            try db.columns(in: "vocabulary_entries").map { $0.name }
        }
        #expect(columnNames.contains("srsState"),    "srsState column must exist")
        #expect(columnNames.contains("dueDate"),     "dueDate column must exist")
        #expect(columnNames.contains("interval"),    "interval column must exist")
        #expect(columnNames.contains("easeFactor"),  "easeFactor column must exist")
        #expect(columnNames.contains("ratingCount"), "ratingCount column must exist")
    }

    @Test("idx_vocabulary_due_date index exists after v4")
    func testDueDateIndexExists() throws {
        let db = try Database(path: ":memory:")
        let indexes = try db.dbQueue.read { db in
            try db.indexes(on: "vocabulary_entries").map { $0.name }
        }
        #expect(indexes.contains("idx_vocabulary_due_date"), "dueDate index must exist")
    }

    // MARK: - Existing rows receive correct defaults

    @Test("rows inserted before v4 receive srsState='new' default")
    func testExistingRowsGetSRSStateDefault() throws {
        // Simulate a pre-v4 legacy row by inserting directly via raw SQL,
        // omitting the srsState column so SQLite fires the DEFAULT 'new'.
        // This mirrors a row that existed before the v4 migration was applied.
        let db = try Database(path: ":memory:")
        _ = try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO vocabulary_entries
                        (englishText, frenchTranslation, translationStatus,
                         seenCount, firstCapturedAt, lastSeenAt, isRetained, triageStatus)
                    VALUES ('antiquated', NULL, 'pending', 1,
                            datetime('now'), datetime('now'), 0, 'unreviewed')
                    """
            )
        }
        let rawState = try db.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT srsState FROM vocabulary_entries WHERE englishText = 'antiquated'")
        }
        #expect(rawState == "new", "Legacy row (no srsState in INSERT) must get DB DEFAULT 'new'")
    }

    @Test("rows inserted before v4 receive interval=1.0 default")
    func testExistingRowsGetIntervalDefault() throws {
        let db = try Database(path: ":memory:")

        _ = try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO vocabulary_entries
                        (englishText, frenchTranslation, translationStatus,
                         seenCount, firstCapturedAt, lastSeenAt, isRetained, triageStatus)
                    VALUES ('legacy_word', NULL, 'pending', 1,
                            datetime('now'), datetime('now'), 0, 'unreviewed')
                    """
            )
        }

        let interval = try db.dbQueue.read { db in
            try Double.fetchOne(db, sql: "SELECT interval FROM vocabulary_entries WHERE englishText = 'legacy_word'")
        }
        #expect(interval == 1.0, "Legacy rows must receive interval DEFAULT 1.0")
    }

    @Test("rows inserted before v4 receive easeFactor=2.5 default")
    func testExistingRowsGetEaseFactorDefault() throws {
        let db = try Database(path: ":memory:")
        _ = try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO vocabulary_entries
                        (englishText, frenchTranslation, translationStatus,
                         seenCount, firstCapturedAt, lastSeenAt, isRetained, triageStatus)
                    VALUES ('ease_test', NULL, 'pending', 1,
                            datetime('now'), datetime('now'), 0, 'unreviewed')
                    """
            )
        }
        let ease = try db.dbQueue.read { db in
            try Double.fetchOne(db, sql: "SELECT easeFactor FROM vocabulary_entries WHERE englishText = 'ease_test'")
        }
        #expect(ease == 2.5, "Legacy rows must receive easeFactor DEFAULT 2.5")
    }

    @Test("rows inserted before v4 receive ratingCount=0 default")
    func testExistingRowsGetRatingCountDefault() throws {
        let db = try Database(path: ":memory:")
        _ = try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO vocabulary_entries
                        (englishText, frenchTranslation, translationStatus,
                         seenCount, firstCapturedAt, lastSeenAt, isRetained, triageStatus)
                    VALUES ('count_test', NULL, 'pending', 1,
                            datetime('now'), datetime('now'), 0, 'unreviewed')
                    """
            )
        }
        let count = try db.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT ratingCount FROM vocabulary_entries WHERE englishText = 'count_test'")
        }
        #expect(count == 0, "Legacy rows must receive ratingCount DEFAULT 0")
    }

    @Test("rows inserted before v4 receive dueDate = NULL default")
    func testExistingRowsGetDueDateDefault() throws {
        // SQLite ALTER TABLE does not support expression defaults such as date('now'),
        // so dueDate defaults to NULL for legacy rows. The real value is set by
        // markSaved() when the user saves the word from the Inbox.
        let db = try Database(path: ":memory:")
        _ = try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO vocabulary_entries
                        (englishText, frenchTranslation, translationStatus,
                         seenCount, firstCapturedAt, lastSeenAt, isRetained, triageStatus)
                    VALUES ('date_test', NULL, 'pending', 1,
                            datetime('now'), datetime('now'), 0, 'unreviewed')
                    """
            )
        }
        let dueDate = try db.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT dueDate FROM vocabulary_entries WHERE englishText = 'date_test'")
        }
        #expect(dueDate == nil, "Legacy rows must receive dueDate DEFAULT NULL (expression defaults are not allowed in ALTER TABLE): got \(dueDate ?? "nil")")
    }

    // MARK: - No existing columns are modified

    @Test("v4 migration does not modify existing columns (englishText, translationStatus, isRetained)")
    func testV4DoesNotModifyExistingColumns() throws {
        let db = try Database(path: ":memory:")
        let repo = VocabularyEntryRepository(dbQueue: db.dbQueue)

        var entry = try repo.upsert(englishText: "immutable")
        entry.frenchTranslation = "immuable"
        entry.translationStatus = .translated
        try repo.update(entry: entry)
        try repo.markRetained(id: entry.id!, true)

        let fetched = try repo.fetchAll().first { $0.englishText == "immutable" }!
        #expect(fetched.englishText       == "immutable")
        #expect(fetched.frenchTranslation == "immuable")
        #expect(fetched.translationStatus == .translated)
        #expect(fetched.isRetained        == true)
        #expect(fetched.seenCount         == 1)
    }
}
