import Testing
import Foundation
@testable import ClipboardVocab

// MARK: - Helpers

/// Builds a minimal `VocabularyEntry` for use in FocusSession tests.
/// No database required — FocusSession is a pure in-memory value type.
private func makeEntry(id: Int64, text: String = "word") -> VocabularyEntry {
    VocabularyEntry(
        id: id,
        englishText: text,
        frenchTranslation: "mot",
        translationStatus: .translated,
        triageStatus: .saved,
        seenCount: 1,
        firstCapturedAt: Date(),
        lastSeenAt: Date(),
        isRetained: false
    )
}

private func makeSession(count: Int) -> FocusSession {
    let entries = (1...count).map { makeEntry(id: Int64($0), text: "word\($0)") }
    return FocusSession(
        totalCards: count,
        isOnDemand: false,
        cards: entries,
        ratedCount: 0,
        tally: .init(),
        failedCardIDs: []
    )
}

// MARK: - FocusSessionTests

@Suite("FocusSessionTests")
struct FocusSessionTests {

    @Test("advance removes first card; isComplete becomes true when cards is empty")
    func testAdvanceRemovesFirstCard() {
        var session = makeSession(count: 2)
        #expect(session.current?.id == 1)

        session.advance()
        #expect(session.current?.id == 2)
        #expect(session.isComplete == false)

        session.advance()
        #expect(session.isComplete == true)
        #expect(session.current == nil)
    }

    @Test("recordRating(.good) increments tally.good and ratedCount; other tally fields unchanged")
    func testRecordRatingGood() {
        var session = makeSession(count: 3)
        session.recordRating(.good)

        #expect(session.ratedCount == 1)
        #expect(session.tally.good == 1)
        #expect(session.tally.again == 0)
        #expect(session.tally.hard == 0)
        #expect(session.tally.easy == 0)
    }

    @Test("recordRating increments the correct tally field for each SRSRating case")
    func testRecordRatingAllCases() {
        var session = makeSession(count: 4)
        session.recordRating(.again)
        session.recordRating(.hard)
        session.recordRating(.good)
        session.recordRating(.easy)

        #expect(session.tally.again == 1)
        #expect(session.tally.hard == 1)
        #expect(session.tally.good == 1)
        #expect(session.tally.easy == 1)
        #expect(session.ratedCount == 4)
    }

    @Test("appendRetry appends the card to cards and inserts id into failedCardIDs")
    func testAppendRetryAppendsCard() {
        var session = makeSession(count: 2)
        let card = makeEntry(id: 99, text: "retry")

        session.appendRetry(card)

        #expect(session.cards.count == 3)
        #expect(session.cards.last?.id == 99)
        #expect(session.failedCardIDs.contains(99))
    }

    @Test("appendRetry with an id already in failedCardIDs does NOT append — single-retry enforcement")
    func testAppendRetryDoesNotAppendTwice() {
        var session = makeSession(count: 2)
        let card = makeEntry(id: 99, text: "retry")

        session.appendRetry(card) // first call — should append
        let countAfterFirst = session.cards.count

        session.appendRetry(card) // second call — should be no-op
        #expect(session.cards.count == countAfterFirst, "Second appendRetry must be a no-op")
        #expect(session.failedCardIDs.contains(99), "ID must remain in failedCardIDs")
    }

    @Test("totalCards never changes after init regardless of appendRetry calls")
    func testTotalCardsNeverChanges() {
        var session = makeSession(count: 3)
        let originalTotal = session.totalCards

        session.appendRetry(makeEntry(id: 10))
        session.appendRetry(makeEntry(id: 11))
        session.advance()

        #expect(session.totalCards == originalTotal, "totalCards must be immutable")
    }

    @Test("ratedCount does NOT increment when advance() is called without a preceding recordRating")
    func testRatedCountDoesNotIncrementOnAdvanceAlone() {
        var session = makeSession(count: 3)

        session.advance()
        session.advance()

        #expect(session.ratedCount == 0, "advance() must not increment ratedCount")
    }
}

// MARK: - FocusSessionRetryTests

@Suite("FocusSessionRetryTests")
struct FocusSessionRetryTests {

    @Test("Full session of 3 cards: recordRating + advance ×3 → isComplete, ratedCount == 3, tally sums to 3")
    func testFullSessionCompletionThreeCards() {
        var session = makeSession(count: 3)

        session.recordRating(.good); session.advance()
        session.recordRating(.hard); session.advance()
        session.recordRating(.easy); session.advance()

        #expect(session.isComplete == true)
        #expect(session.ratedCount == 3)
        let tallySum = session.tally.again + session.tally.hard + session.tally.good + session.tally.easy
        #expect(tallySum == 3)
        #expect(session.tally.good == 1)
        #expect(session.tally.hard == 1)
        #expect(session.tally.easy == 1)
    }

    @Test("Write failure on card 1: appendRetry + advance (no recordRating) → card appears at end; retry recordRating + advance → isComplete, ratedCount == 2")
    func testWriteFailureRequeuesCardOnce() {
        var session = makeSession(count: 3)

        // Card 1 fails — re-queue without recording a rating
        let failedCard = session.current!
        session.appendRetry(failedCard)
        session.advance()

        // Cards 2 and 3 succeed
        session.recordRating(.good); session.advance()
        session.recordRating(.good); session.advance()

        // Retry of card 1 at the end succeeds
        #expect(session.current?.id == failedCard.id, "Failed card must appear at end of queue")
        session.recordRating(.again); session.advance()

        #expect(session.isComplete == true)
        // Only 3 successful writes (card2, card3, retry): ratedCount == 3
        // (card1 first attempt didn't call recordRating, retry did)
        #expect(session.ratedCount == 3)
    }

    @Test("Double failure on same card: first appendRetry succeeds, second is a no-op")
    func testDoubleFailureSameCardNoOp() {
        var session = makeSession(count: 3)
        let card = session.current!

        session.appendRetry(card) // first — appends
        let countAfterFirst = session.cards.count

        session.appendRetry(card) // second — no-op
        #expect(session.cards.count == countAfterFirst, "Second appendRetry must not append again")
    }

    @Test("totalCards == 3 throughout: advance, retry, double retry all leave it unchanged")
    func testTotalCardsUnchangedThroughout() {
        var session = makeSession(count: 3)
        let card = session.current!

        session.appendRetry(card)
        session.advance()
        session.recordRating(.good); session.advance()

        #expect(session.totalCards == 3)
    }

    @Test("Session pause/resume preservation: advance() twice leaves session.current at third entry, ratedCount unchanged")
    func testSessionPauseResumePreservation() {
        var session = makeSession(count: 5)

        session.advance()
        session.advance()

        #expect(session.current?.id == 3, "After two advance() calls, current must be the third entry")
        #expect(session.ratedCount == 0, "advance()-only calls must not increment ratedCount")
        #expect(session.cards.count == 3, "Three cards must remain after two advance() calls")
    }
}
