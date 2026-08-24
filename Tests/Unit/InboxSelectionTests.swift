import Testing
import Foundation
import GRDB
@testable import ClipboardVocab

/// Tests for Epic 5 — Inbox selection: deleteAll and selection state invariants.
///
/// Note: `@State` fields (`isSelecting`, `selectedIDs`) are pure SwiftUI view state
/// and cannot be directly unit-tested without a hosting environment. These tests
/// instead verify the repository-level contracts that back the selection actions
/// (C-21–C-25, C-37–C-38, C-41).
@Suite("InboxSelectionTests")
struct InboxSelectionTests {

    // MARK: - Helpers

    private func makeRepo() throws -> VocabularyEntryRepository {
        let db = try Database(path: ":memory:")
        return VocabularyEntryRepository(dbQueue: db.dbQueue)
    }

    private func insertEntries(_ texts: [String], repo: VocabularyEntryRepository) throws -> [Int64] {
        try texts.map { text in
            let entry = try repo.upsert(englishText: text)
            return entry.id!
        }
    }

    // MARK: - deleteAll contract tests (C-21 – C-25)

    @Test("deleteAll removes all specified IDs in a single transaction")
    func testDeleteAllRemovesAllSpecified() throws {
        let repo = try makeRepo()
        let ids = try insertEntries(["alpha", "beta", "gamma"], repo: repo)

        try repo.deleteAll(ids: ids)

        let remaining = try repo.fetchAll()
        #expect(remaining.isEmpty, "deleteAll must remove all specified entries")
    }

    @Test("deleteAll is a no-op when given an empty array (C-23)")
    func testDeleteAllEmptyIsNoOp() throws {
        let repo = try makeRepo()
        _ = try insertEntries(["alpha", "beta"], repo: repo)

        try repo.deleteAll(ids: [])

        let remaining = try repo.fetchAll()
        #expect(remaining.count == 2, "deleteAll([]) must not remove any entries")
    }

    @Test("deleteAll does not throw and leaves unspecified entries intact")
    func testDeleteAllDoesNotAffectOtherEntries() throws {
        let repo = try makeRepo()
        let ids = try insertEntries(["to_delete", "to_keep_a", "to_keep_b"], repo: repo)
        let deleteId = ids[0]
        let keepIds = Array(ids.dropFirst())

        try repo.deleteAll(ids: [deleteId])

        let remaining = try repo.fetchAll()
        let remainingIds = remaining.compactMap { $0.id }
        #expect(!remainingIds.contains(deleteId), "Deleted entry must not remain")
        for keepId in keepIds {
            #expect(remainingIds.contains(keepId), "Non-deleted entry must remain")
        }
    }

    @Test("deleteAll is idempotent: calling it twice with the same IDs does not throw")
    func testDeleteAllIdempotent() throws {
        let repo = try makeRepo()
        let ids = try insertEntries(["word1", "word2"], repo: repo)

        try repo.deleteAll(ids: ids)
        // Second call: rows are already gone; must not throw
        #expect(throws: Never.self) {
            try repo.deleteAll(ids: ids)
        }
    }

    // MARK: - Selection state invariants (C-34, C-41, C-43)

    @Test("newly upserted entry after observation start has isMastered = false (C-42 DB side)")
    func testNewEntryHasIsMasteredFalse() throws {
        let repo = try makeRepo()
        let entry = try repo.upsert(englishText: "ephemeral")
        #expect(entry.isMastered == false, "Any new entry must have isMastered = false")
    }

    @Test("Inbox fetch (fetchAll) includes mastered entries — mastery only excludes from Learn queue (C-43)")
    func testInboxShowsMasteredEntries() throws {
        let repo = try makeRepo()
        let entry = try repo.upsert(englishText: "mastered_word")
        guard let id = entry.id else { Issue.record("Expected id"); return }
        try repo.markSaved(id: id)
        try repo.markMastered(id: id)

        // fetchAll (which backs the Inbox observation) still returns the mastered entry
        let all = try repo.fetchAll()
        let found = all.first { $0.id == id }
        #expect(found != nil, "Mastered entry must remain visible in Inbox (fetchAll)")
        #expect(found?.isMastered == true)
    }

    // MARK: - Session construction for Add to Learn (C-40)

    @Test("FocusSession constructed from selection has isOnDemand = true and correct totalCards")
    func testAddToLearnSessionConstruction() throws {
        let repo = try makeRepo()
        let ids = try insertEntries(["alpha", "beta", "gamma"], repo: repo)
        let selectedEntries = try repo.fetchAll().filter { ids.prefix(2).contains($0.id ?? -1) }

        let session = FocusSession(
            totalCards: selectedEntries.count,
            isOnDemand: true,
            cards: selectedEntries,
            ratedCount: 0,
            tally: .init(),
            failedCardIDs: []
        )

        #expect(session.isOnDemand == true, "Add to Learn session must have isOnDemand = true")
        #expect(session.totalCards == 2)
        #expect(session.cards.count == 2)
    }

    @Test("FocusSession with isOnDemand = false for normal SRS queue session")
    func testNormalSessionIsNotOnDemand() throws {
        let repo = try makeRepo()
        let e = try repo.upsert(englishText: "normal")
        let session = FocusSession(
            totalCards: 1,
            isOnDemand: false,
            cards: [e],
            ratedCount: 0,
            tally: .init(),
            failedCardIDs: []
        )
        #expect(session.isOnDemand == false)
    }
}
