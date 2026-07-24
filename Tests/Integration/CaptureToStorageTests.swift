import Testing
import Foundation
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
}
