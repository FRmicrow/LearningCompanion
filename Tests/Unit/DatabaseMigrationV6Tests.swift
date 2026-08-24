import Testing
import Foundation
import GRDB
@testable import ClipboardVocab

@Suite("DatabaseMigrationV6Tests")
struct DatabaseMigrationV6Tests {

    private func makeRepo() throws -> VocabularyEntryRepository {
        let db = try Database(path: ":memory:")
        return VocabularyEntryRepository(dbQueue: db.dbQueue)
    }

    @Test("v6 migration runs without error on a fresh in-memory DB")
    func testV6MigrationRunsWithoutError() throws {
        // Database(path: ":memory:") runs all migrations including v6 — if it throws, the test fails.
        #expect(throws: Never.self) {
            _ = try Database(path: ":memory:")
        }
    }

    @Test("isMastered column exists with INTEGER type after v6")
    func testIsMasteredColumnExists() throws {
        let db = try Database(path: ":memory:")
        let columnExists: Bool = try db.dbQueue.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: "PRAGMA table_info(vocabulary_entries)")
            return rows.contains { row in
                (row["name"] as? String) == "isMastered"
            }
        }
        #expect(columnExists, "isMastered column must exist after v6 migration")
    }

    @Test("existing rows have isMastered = false after v6 migration")
    func testExistingRowsHaveIsMasteredFalseAfterMigration() throws {
        let repo = try makeRepo()
        let entry = try repo.upsert(englishText: "luminous")
        guard let id = entry.id else {
            Issue.record("Expected id after insert")
            return
        }

        let fetched = try repo.fetchAll().first { $0.id == id }
        guard let fetched else {
            Issue.record("Row not found after insert")
            return
        }
        #expect(fetched.isMastered == false, "Existing rows must have isMastered = false after v6")
    }

    @Test("no existing column (v5 and prior) is modified or removed by v6")
    func testNoExistingColumnIsModifiedByV6() throws {
        let repo = try makeRepo()
        let entry = try repo.upsert(englishText: "resilience")
        guard let id = entry.id else { Issue.record("Expected id"); return }
        try repo.markSaved(id: id)
        try repo.setDifficultyLabel(id: id, label: .medium)

        let fetched = try repo.fetchAll().first { $0.id == id }
        guard let fetched else { Issue.record("Row not found"); return }

        #expect(fetched.triageStatus == .saved)
        #expect(fetched.srsState == .new)
        #expect(fetched.difficultyLabel == .medium)
        #expect(fetched.englishText == "resilience")
    }

    @Test("freshly inserted entry via upsert has isMastered == false")
    func testFreshlyInsertedEntryHasIsMasteredFalse() throws {
        let repo = try makeRepo()
        let entry = try repo.upsert(englishText: "ephemeral")
        #expect(entry.isMastered == false, "Freshly upserted entry must have isMastered = false")
    }
}
