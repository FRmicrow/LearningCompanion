import Testing
import Foundation
import GRDB
@testable import ClipboardVocab

@Suite("VocabularyEntryRepository Tests")
struct VocabularyEntryRepositoryTests {

    // MARK: - Helpers

    private func makeRepo() throws -> VocabularyEntryRepository {
        let db = try Database(path: ":memory:")
        return VocabularyEntryRepository(dbQueue: db.dbQueue)
    }

    // MARK: - Tests

    @Test("Insert creates entry with seenCount = 1")
    func testInsertCreatesEntryWithSeenCountOne() throws {
        let repo = try makeRepo()

        let entry = try repo.upsert(englishText: "threshold")

        #expect(entry.id != nil)
        #expect(entry.englishText == "threshold")
        #expect(entry.seenCount == 1)
        #expect(entry.translationStatus == .pending)
        #expect(entry.frenchTranslation == nil)
    }

    @Test("Re-insert increments seenCount, no duplicate row")
    func testReInsertIncrementsSeenCountNoDuplicate() throws {
        let repo = try makeRepo()

        _ = try repo.upsert(englishText: "serendipity")
        let updated = try repo.upsert(englishText: "serendipity")

        #expect(updated.seenCount == 2)

        let all = try repo.fetchAll()
        #expect(all.count == 1, "Must not create duplicate rows")
    }

    @Test("Delete removes the row")
    func testDeleteRemovesRow() throws {
        let repo = try makeRepo()

        let entry = try repo.upsert(englishText: "ephemeral")
        guard let id = entry.id else {
            Issue.record("Expected id after insert")
            return
        }
        try repo.delete(id: id)

        let all = try repo.fetchAll()
        #expect(all.isEmpty)
    }

    @Test("Re-capture after delete creates fresh entry with seenCount = 1")
    func testReCaptureAfterDeleteCreatesFreshEntry() throws {
        let repo = try makeRepo()

        let entry = try repo.upsert(englishText: "resilience")
        guard let id = entry.id else {
            Issue.record("Expected id after insert")
            return
        }
        try repo.delete(id: id)

        let fresh = try repo.upsert(englishText: "resilience")
        #expect(fresh.seenCount == 1)
        #expect(fresh.id != id, "Fresh row should have a different id")
    }

    @Test("fetchPending returns only pending entries")
    func testFetchPendingReturnsOnlyPendingEntries() throws {
        let repo = try makeRepo()

        var e1 = try repo.upsert(englishText: "word1")
        e1.frenchTranslation = "mot1"
        e1.translationStatus = .translated
        try repo.update(entry: e1)

        _ = try repo.upsert(englishText: "word2") // remains pending

        let pending = try repo.fetchPending()
        #expect(pending.count == 1)
        #expect(pending[0].englishText == "word2")
    }

    @Test("fetchAll returns entries ordered most-recent first")
    func testFetchAllOrderedMostRecentFirst() throws {
        let repo = try makeRepo()

        _ = try repo.upsert(englishText: "alpha")
        Thread.sleep(forTimeInterval: 0.05)
        _ = try repo.upsert(englishText: "beta")

        let all = try repo.fetchAll()
        #expect(all.first?.englishText == "beta")
        #expect(all.last?.englishText == "alpha")
    }
}

// MARK: - isRetained tests (T006, T007)

extension VocabularyEntryRepositoryTests {

    @Test("markRetained persists true")
    func testMarkRetained_persistsTrue() throws {
        let repo = try makeRepo()
        let entry = try repo.upsert(englishText: "eloquent")
        guard let id = entry.id else {
            Issue.record("Expected id after insert")
            return
        }

        try repo.markRetained(id: id, true)

        let all = try repo.fetchAll()
        #expect(all.first?.isRetained == true)
    }

    @Test("markRetained persists false after being set true")
    func testMarkRetained_persistsFalse() throws {
        let repo = try makeRepo()
        let entry = try repo.upsert(englishText: "pensive")
        guard let id = entry.id else {
            Issue.record("Expected id after insert")
            return
        }

        try repo.markRetained(id: id, true)
        try repo.markRetained(id: id, false)

        let all = try repo.fetchAll()
        #expect(all.first?.isRetained == false)
    }

    @Test("fetchOldUnretained excludes retained entries")
    func testFetchOldUnretained_excludesRetained() throws {
        let repo = try makeRepo()
        let cutoff = Date()

        // Insert old entries directly using repo.upsert + update to backdate
        var old1 = try repo.upsert(englishText: "archaic")
        old1.firstCapturedAt = Date(timeIntervalSinceNow: -8 * 24 * 3600)
        old1.lastSeenAt = old1.firstCapturedAt
        try repo.update(entry: old1)

        var old2 = try repo.upsert(englishText: "obsolete")
        old2.firstCapturedAt = Date(timeIntervalSinceNow: -9 * 24 * 3600)
        old2.lastSeenAt = old2.firstCapturedAt
        try repo.update(entry: old2)

        // Retain old2
        guard let id2 = old2.id else { Issue.record("Expected id"); return }
        try repo.markRetained(id: id2, true)

        let results = try repo.fetchOldUnretained(before: cutoff)
        #expect(results.count == 1)
        #expect(results[0].englishText == "archaic")
    }

    @Test("fetchOldUnretained excludes entries newer than cutoff")
    func testFetchOldUnretained_excludesNewEntries() throws {
        let repo = try makeRepo()
        let cutoff = Date(timeIntervalSinceNow: -7 * 24 * 3600)

        var old = try repo.upsert(englishText: "antique")
        old.firstCapturedAt = Date(timeIntervalSinceNow: -10 * 24 * 3600)
        old.lastSeenAt = old.firstCapturedAt
        try repo.update(entry: old)

        // Recent entry — should NOT appear
        _ = try repo.upsert(englishText: "modern")

        let results = try repo.fetchOldUnretained(before: cutoff)
        #expect(results.count == 1)
        #expect(results[0].englishText == "antique")
    }
}

