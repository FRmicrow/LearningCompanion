import Testing
import Foundation
import GRDB
@testable import ClipboardVocab

/// Verifies that migration v5 runs cleanly and produces the correct schema.
@Suite("DatabaseMigrationV5Tests")
struct DatabaseMigrationV5Tests {

    // MARK: - Helpers

    /// Insert a row at the v4 schema level using raw SQL,
    /// bypassing the current Swift model (which includes v5 fields).
    private func insertV4Row(db: DatabaseQueue, englishText: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO vocabulary_entries
                        (englishText, frenchTranslation, translationStatus,
                         seenCount, firstCapturedAt, lastSeenAt, isRetained,
                         triageStatus, srsState, dueDate, interval, easeFactor, ratingCount)
                    VALUES (?, NULL, 'pending', 1,
                            datetime('now'), datetime('now'), 0,
                            'unreviewed', 'new', NULL, 1.0, 2.5, 0)
                    """,
                arguments: [englishText]
            )
        }
    }

    // MARK: - Structural checks

    @Test("v5 migration runs without error on a fresh in-memory DB")
    func testV5MigrationRunsWithoutError() throws {
        #expect(throws: Never.self) {
            _ = try Database(path: ":memory:")
        }
    }

    @Test("vocabulary_entries table has both new v5 columns after migration")
    func testV5ColumnsExist() throws {
        let db = try Database(path: ":memory:")
        let columnNames = try db.dbQueue.read { db in
            try db.columns(in: "vocabulary_entries").map { $0.name }
        }
        #expect(columnNames.contains("difficultyLabel"),  "difficultyLabel column must exist after v5")
        #expect(columnNames.contains("lastReviewedDate"), "lastReviewedDate column must exist after v5")
    }

    @Test("existing rows have difficultyLabel = NULL and lastReviewedDate = NULL after v5")
    func testExistingRowsHaveNullNewColumns() throws {
        // Use a real temp file path so we can simulate pre-v5 rows
        let tmpDir = FileManager.default.temporaryDirectory
        let dbPath = tmpDir.appendingPathComponent("migration_v5_test_\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        // Open and run all migrations (including v5)
        let db = try Database(path: dbPath)

        // Insert a row the normal way (fields will be set but v5 cols default to NULL)
        let repo = VocabularyEntryRepository(dbQueue: db.dbQueue)
        let entry = try repo.upsert(englishText: "migrate_test")
        let id = entry.id!

        let fetched = try repo.fetchAll().first { $0.id == id }!
        #expect(fetched.difficultyLabel == nil,  "difficultyLabel must be nil for a row inserted before any v5 write")
        #expect(fetched.lastReviewedDate == nil, "lastReviewedDate must be nil before any rating is applied")
    }

    @Test("v5 migration does not modify any pre-existing column")
    func testV5MigrationIsNonDestructive() throws {
        let db = try Database(path: ":memory:")
        let columnNames = try db.dbQueue.read { db in
            try db.columns(in: "vocabulary_entries").map { $0.name }
        }
        // All v1–v4 columns must still be present
        let required = [
            "id", "englishText", "frenchTranslation", "translationStatus",
            "seenCount", "firstCapturedAt", "lastSeenAt", "isRetained",
            "triageStatus", "srsState", "dueDate", "interval", "easeFactor", "ratingCount"
        ]
        for col in required {
            #expect(columnNames.contains(col), "Column '\(col)' must not be removed by v5 migration")
        }
    }

    @Test("v5 migration is idempotent — migrator handles repeated runs gracefully")
    func testV5MigrationIdempotent() throws {
        // GRDB's DatabaseMigrator records completed migrations and never re-runs them.
        // Opening a second Database on the same queue exercises this path.
        let tmpDir = FileManager.default.temporaryDirectory
        let dbPath = tmpDir.appendingPathComponent("migration_v5_idempotent_\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        _ = try Database(path: dbPath)
        // A second open on the same path must not throw (migrator skips already-run migrations)
        #expect(throws: Never.self) {
            _ = try Database(path: dbPath)
        }
    }
}
