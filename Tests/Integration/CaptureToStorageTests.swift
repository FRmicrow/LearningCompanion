import Testing
import Foundation
import GRDB
@testable import ClipboardVocab

/// Integration test: simulates the full pipeline from clipboard event → DB insert.
@Suite("CaptureToStorage Integration Tests")
actor CaptureToStorageTests: CaptureProcessorDelegate {

    // MARK: - State

    var repo: VocabularyEntryRepository!
    var processor: CaptureProcessorService!
    var storedEntries: [VocabularyEntry] = []

    // MARK: - Setup

    init() async throws {
        let db = try Database(path: ":memory:")
        repo = VocabularyEntryRepository(dbQueue: db.dbQueue)
        let translator = TranslationService(repository: repo)
        processor = CaptureProcessorService(
            languageDetector: LanguageDetectionService(),
            translationService: translator,
            repository: repo
        )
        processor.delegate = self
    }

    // MARK: - CaptureProcessorDelegate

    nonisolated func captureProcessor(_ processor: CaptureProcessorService,
                                      didStore entry: VocabularyEntry) {
        Task { await self.appendStored(entry) }
    }

    nonisolated func captureProcessor(_ processor: CaptureProcessorService,
                                      didDiscard text: String, reason: DiscardReason) {}

    private func appendStored(_ entry: VocabularyEntry) { storedEntries.append(entry) }

    // MARK: - Tests

    @Test("Clipboard capture round-trip stores entry in DB")
    func testCaptureToStorageRoundTrip() async throws {
        let start = Date()
        // Use a phrase NLLanguageRecognizer reliably identifies as English
        await processor.process(text: "good morning")
        let elapsed = Date().timeIntervalSince(start) * 1000

        let all = try repo.fetchAll()
        #expect(all.count == 1)
        #expect(all[0].englishText == "good morning")
        #expect(all[0].seenCount == 1)

        // Pipeline should complete well within 5 seconds even without network
        #expect(elapsed < 5000, "Pipeline should complete within 5s")
    }

    @Test("SC-001: capture latency ≤ 3000ms to DB insert")
    func testCaptureLatencyWithinThreeSeconds() async throws {
        let start = Date()
        // "good morning" reliably passes NLLanguageRecognizer as English
        await processor.process(text: "good morning")
        let elapsed = Date().timeIntervalSince(start) * 1000

        let all = try repo.fetchAll()
        #expect(!all.isEmpty, "Entry must be in DB")

        // SC-001: pipeline (excluding network translation) must be ≤ 3000ms
        #expect(elapsed <= 3000, "SC-001: capture must complete within 3 seconds")
    }

    // MARK: - SRS rating round-trip (T016, T017, T018)

    // T016: documents the end-to-end rating path:
    //   1. entry = repo.upsert → repo.markSaved
    //   2. let update = SRSEngine.rate(entry, rating: .good)
    //   3. try repo.applyRating(id: entry.id!, update: update)
    // This sequence is exercised directly in T017 and T018 below.

    @Test("T017 ratingRoundTrip: saved entry enters queue, Good rating removes it and sets correct dueDate")
    func testRatingRoundTrip() throws {
        // Capture → markSaved → appears in daily queue
        let entry = try repo.upsert(englishText: "luminous")
        guard let id = entry.id else { Issue.record("Expected id after upsert"); return }
        try repo.markSaved(id: id)

        let dueBefore = try repo.fetchDueEntries()
        #expect(dueBefore.contains { $0.id == id }, "Entry must appear in daily queue after markSaved")

        // Rate Good
        let saved = try repo.fetchAll().first { $0.id == id }!
        let update = SRSEngine.rate(saved, rating: .good)
        // Verify the update has a future dueDate so it leaves today's queue
        // newInterval = 1.0 × 2.5 = 2.5 → round(2.5) days
        let expectedDueDate = dateString(addingDays: Int((2.5).rounded()))
        #expect(update.dueDate == expectedDueDate, "Good rating dueDate should be today + round(2.5)")

        try repo.applyRating(id: id, update: update)

        // Entry must no longer appear in today's queue (dueDate is in the future)
        let dueAfter = try repo.fetchDueEntries()
        #expect(!dueAfter.contains { $0.id == id }, "Entry must leave daily queue after Good rating")

        // Verify the DB row has updated SRS fields
        let updated = try repo.fetchAll().first { $0.id == id }!
        #expect(updated.dueDate     == expectedDueDate)
        #expect(updated.ratingCount == 1)
        #expect(updated.srsState    == .learning)
    }

    @Test("T018 againRatingResetsInterval: interval resets to 1.0, dueDate = tomorrow, srsState = .learning")
    func testAgainRatingResetsInterval() throws {
        // Insert entry with a non-default interval to confirm it resets
        let entry = try repo.upsert(englishText: "ephemeral")
        guard let id = entry.id else { Issue.record("Expected id"); return }
        try repo.markSaved(id: id)

        // Manually advance the interval to 10.0 (simulating prior ratings)
        try repo.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE vocabulary_entries SET interval = 10.0, ratingCount = 4 WHERE id = ?",
                arguments: [id]
            )
        }

        let withInterval = try repo.fetchAll().first { $0.id == id }!
        #expect(withInterval.interval == 10.0)

        // Rate Again
        let update = SRSEngine.rate(withInterval, rating: .again)
        try repo.applyRating(id: id, update: update)

        let result = try repo.fetchAll().first { $0.id == id }!
        #expect(result.interval    == 1.0,           "Again must reset interval to 1.0")
        #expect(result.dueDate     == dateString(addingDays: 1), "Again sets dueDate to tomorrow")
        #expect(result.srsState    == .learning,     "Again from any state → .learning")
        #expect(result.ratingCount == 5,             "ratingCount increments from 4 to 5")
    }

    // MARK: - Helpers

    private func dateString(addingDays days: Int) -> String {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date())) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar   = cal
        return fmt.string(from: date)
    }
}
