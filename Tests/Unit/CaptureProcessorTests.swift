import Testing
@testable import ClipboardVocab

@Suite("CaptureProcessor Tests")
actor CaptureProcessorTests: CaptureProcessorDelegate {

    // MARK: - State

    var discardedReasons: [DiscardReason] = []
    var storedEntries: [VocabularyEntry] = []
    var repo: VocabularyEntryRepository!
    var processor: CaptureProcessorService!

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
                                      didDiscard text: String,
                                      reason: DiscardReason) {
        Task { await self.appendDiscard(reason) }
    }

    private func appendStored(_ entry: VocabularyEntry) { storedEntries.append(entry) }
    private func appendDiscard(_ reason: DiscardReason) { discardedReasons.append(reason) }

    // MARK: - Discard path tests

    @Test("Text longer than 50 chars is discarded as tooLong")
    func testTooLongIsDiscarded() async {
        let longText = String(repeating: "a", count: 51)
        await processor.process(text: longText)
        try? await Task.sleep(nanoseconds: 100_000_000) // let callbacks settle
        #expect(discardedReasons.last == .tooLong)
        #expect(storedEntries.isEmpty)
    }

    @Test("URL is discarded as noMeaningfulLanguage")
    func testURLIsDiscarded() async {
        await processor.process(text: "https://example.com/page")
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(discardedReasons.last == .noMeaningfulLanguage)
        #expect(storedEntries.isEmpty)
    }

    @Test("Numeric string is discarded as noMeaningfulLanguage")
    func testNumericStringIsDiscarded() async {
        await processor.process(text: "12345")
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(discardedReasons.last == .noMeaningfulLanguage)
        #expect(storedEntries.isEmpty)
    }

    @Test("UNIX path is discarded as noMeaningfulLanguage")
    func testUnixPathIsDiscarded() async {
        await processor.process(text: "/usr/local/bin/app")
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(discardedReasons.last == .noMeaningfulLanguage)
        #expect(storedEntries.isEmpty)
    }

    @Test("French input is discarded as notEnglish or lowConfidence")
    func testFrenchInputIsDiscarded() async {
        await processor.process(text: "bonjour le monde")
        try? await Task.sleep(nanoseconds: 100_000_000)
        let reason = discardedReasons.last
        #expect(reason == .notEnglish || reason == .lowConfidence,
                "Expected .notEnglish or .lowConfidence")
        #expect(storedEntries.isEmpty)
    }

    @Test("51-char English text is discarded as tooLong")
    func testFiftyOneCharEnglishIsDiscarded() async {
        let text = String(repeating: "a", count: 51)
        await processor.process(text: text)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(discardedReasons.last == .tooLong)
    }

    @Test("English phrase triggers upsert and store")
    func testEnglishWordTriggersUpsert() async {
        // Use a phrase NLLanguageRecognizer reliably identifies as English
        await processor.process(text: "good morning")
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(!storedEntries.isEmpty, "English phrase should produce a stored entry")
        #expect(storedEntries.first?.englishText == "good morning")
    }

    @Test("Same phrase twice increments counter, no duplicate row")
    func testSameWordTwiceIncrementsCounterNoDuplicate() async {
        await processor.process(text: "good morning")
        await processor.process(text: "good morning")
        try? await Task.sleep(nanoseconds: 200_000_000)
        let all = try? repo.fetchAll()
        #expect(all?.count == 1, "Must not create duplicate rows")
        #expect(all?.first?.seenCount == 2)
    }
}
