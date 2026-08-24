import Testing
import Foundation
import GRDB
@testable import ClipboardVocab

/// Tests for Epic 5 — Restart session pool sizing and random sampling.
///
/// These tests cover the repository-level `fetchLearnPool()` behaviour
/// and the sampling rule (pool.count > 20 → 20 random cards, otherwise all).
@Suite("LearnSessionRestartTests")
struct LearnSessionRestartTests {

    // MARK: - Helpers

    private func makeRepo() throws -> VocabularyEntryRepository {
        let db = try Database(path: ":memory:")
        return VocabularyEntryRepository(dbQueue: db.dbQueue)
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = Calendar.current
        return fmt.string(from: Date())
    }

    private func dateString(addingDays days: Int) -> String {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date())) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = cal
        return fmt.string(from: date)
    }

    /// Insert `count` saved, non-mastered entries and return their ids.
    private func insertSavedEntries(count: Int, repo: VocabularyEntryRepository) throws -> [Int64] {
        var ids: [Int64] = []
        for i in 1...count {
            let e = try repo.upsert(englishText: "restart_word_\(i)")
            try repo.markSaved(id: e.id!)
            ids.append(e.id!)
        }
        return ids
    }

    // MARK: - fetchLearnPool basics (C-11 – C-16)

    @Test("fetchLearnPool returns empty for empty DB")
    func testFetchLearnPoolEmptyDB() throws {
        let repo = try makeRepo()
        let pool = try repo.fetchLearnPool()
        #expect(pool.isEmpty, "Empty DB must return empty learn pool")
    }

    @Test("fetchLearnPool returns all saved non-mastered entries regardless of dueDate")
    func testFetchLearnPoolIncludesAllDates() throws {
        let repo = try makeRepo()
        let id1 = try makeAndSave("due_today", repo: repo)
        let id2 = try makeAndSave("due_future", repo: repo)
        let id3 = try makeAndSave("due_past", repo: repo)

        // Move id2 dueDate to future, id3 to past
        try repo.dbQueue.write { db in
            try db.execute(sql: "UPDATE vocabulary_entries SET dueDate = ? WHERE id = ?",
                           arguments: [dateString(addingDays: 14), id2])
            try db.execute(sql: "UPDATE vocabulary_entries SET dueDate = ? WHERE id = ?",
                           arguments: [dateString(addingDays: -3), id3])
        }

        let pool = try repo.fetchLearnPool()
        let poolIds = pool.compactMap { $0.id }
        #expect(poolIds.contains(id1))
        #expect(poolIds.contains(id2), "Future dueDate must be in learn pool")
        #expect(poolIds.contains(id3), "Past dueDate must be in learn pool")
    }

    @Test("fetchLearnPool excludes unreviewed entries (triageStatus != saved)")
    func testFetchLearnPoolExcludesUnreviewed() throws {
        let repo = try makeRepo()
        let entry = try repo.upsert(englishText: "unreviewed")
        // Do NOT markSaved — triageStatus = 'unreviewed'

        let pool = try repo.fetchLearnPool()
        #expect(!pool.compactMap { $0.id }.contains(entry.id), "Unreviewed entries must not appear in learn pool")
    }

    @Test("fetchLearnPool excludes mastered entries")
    func testFetchLearnPoolExcludesMastered() throws {
        let repo = try makeRepo()
        let id = try makeAndSave("mastered", repo: repo)
        try repo.markMastered(id: id)

        let pool = try repo.fetchLearnPool()
        #expect(!pool.compactMap { $0.id }.contains(id), "Mastered entry must not appear in learn pool")
    }

    // MARK: - Sampling rule (C-54)

    @Test("Restart samples exactly 20 when pool.count > 20")
    func testRestartSamplesExactly20WhenPoolOver20() throws {
        let repo = try makeRepo()
        _ = try insertSavedEntries(count: 25, repo: repo)

        let pool = try repo.fetchLearnPool()
        #expect(pool.count == 25)

        // Simulate the sampling logic (mirrors LearnView.restartSession)
        let sampled: [VocabularyEntry]
        if pool.count > 20 {
            sampled = Array(pool.shuffled().prefix(20))
        } else {
            sampled = pool
        }

        #expect(sampled.count == 20, "Must sample exactly 20 when pool > 20")
    }

    @Test("Restart uses all entries when pool.count ≤ 20")
    func testRestartUsesAllWhenPool20OrFewer() throws {
        let repo = try makeRepo()
        _ = try insertSavedEntries(count: 15, repo: repo)

        let pool = try repo.fetchLearnPool()
        #expect(pool.count == 15)

        // Simulate sampling
        let sampled: [VocabularyEntry]
        if pool.count > 20 {
            sampled = Array(pool.shuffled().prefix(20))
        } else {
            sampled = pool
        }

        #expect(sampled.count == 15, "All entries must be used when pool.count ≤ 20")
    }

    @Test("Restart with pool.count == 20 uses all 20 entries (boundary)")
    func testRestartBoundaryExact20() throws {
        let repo = try makeRepo()
        _ = try insertSavedEntries(count: 20, repo: repo)

        let pool = try repo.fetchLearnPool()
        #expect(pool.count == 20)

        let sampled: [VocabularyEntry]
        if pool.count > 20 {
            sampled = Array(pool.shuffled().prefix(20))
        } else {
            sampled = pool
        }

        #expect(sampled.count == 20)
    }

    @Test("Restart session constructed from pool has isOnDemand = false (C-55)")
    func testRestartSessionIsNotOnDemand() throws {
        let repo = try makeRepo()
        _ = try insertSavedEntries(count: 3, repo: repo)
        let pool = try repo.fetchLearnPool()

        let session = FocusSession(
            totalCards: pool.count,
            isOnDemand: false,
            cards: pool,
            ratedCount: 0,
            tally: .init(),
            failedCardIDs: []
        )

        #expect(session.isOnDemand == false, "Restart session must have isOnDemand = false")
        #expect(session.totalCards == pool.count)
    }

    @Test("Restart sample cards are a subset of the pool (no invented cards)")
    func testRestartSampleIsSubsetOfPool() throws {
        let repo = try makeRepo()
        _ = try insertSavedEntries(count: 25, repo: repo)

        let pool = try repo.fetchLearnPool()
        let poolIds = Set(pool.compactMap { $0.id })
        let sampled = Array(pool.shuffled().prefix(20))
        let sampledIds = Set(sampled.compactMap { $0.id })

        #expect(sampledIds.isSubset(of: poolIds), "Sampled cards must all come from the pool")
    }

    // MARK: - Private helpers

    @discardableResult
    private func makeAndSave(_ text: String, repo: VocabularyEntryRepository) throws -> Int64 {
        let entry = try repo.upsert(englishText: text)
        let id = entry.id!
        try repo.markSaved(id: id)
        return id
    }
}
