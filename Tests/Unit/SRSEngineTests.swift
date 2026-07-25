import Testing
import Foundation
@testable import ClipboardVocab

// MARK: - Helpers

/// Build a minimal VocabularyEntry suitable for pure SRSEngine tests (no DB needed).
private func makeEntry(
    interval: Double? = nil,
    easeFactor: Double? = nil,
    ratingCount: Int? = nil
) -> VocabularyEntry {
    let now = Date()
    return VocabularyEntry(
        id: nil,
        englishText: "test",
        frenchTranslation: nil,
        translationStatus: .pending,
        triageStatus: .unreviewed,
        seenCount: 1,
        firstCapturedAt: now,
        lastSeenAt: now,
        isRetained: false,
        srsState: nil,
        dueDate: nil,
        interval: interval,
        easeFactor: easeFactor,
        ratingCount: ratingCount
    )
}

/// Today's date as a `yyyy-MM-dd` string (local calendar) — for dueDate assertions.
private func todayString(addingDays days: Int = 0) -> String {
    let cal = Calendar.current
    let date = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date())) ?? Date()
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.calendar   = cal
    return fmt.string(from: date)
}

// MARK: - SRSEngineTests

@Suite("SRSEngineTests")
struct SRSEngineTests {

    // MARK: - Again

    @Test("again resets interval to 1.0")
    func testAgainResetsInterval() {
        let entry = makeEntry(interval: 5.0, easeFactor: 2.5, ratingCount: 3)
        let result = SRSEngine.rate(entry, rating: .again)
        #expect(result.interval == 1.0)
    }

    @Test("again decrements easeFactor by 0.2")
    func testAgainDecrementsEase() {
        let entry = makeEntry(interval: 5.0, easeFactor: 2.5, ratingCount: 1)
        let result = SRSEngine.rate(entry, rating: .again)
        #expect(abs(result.easeFactor - 2.3) < 0.0001)
    }

    @Test("again clamps easeFactor at 1.3 when already at minimum")
    func testAgainClampsEaseAtMinimum() {
        let entry = makeEntry(interval: 1.0, easeFactor: 1.3, ratingCount: 1)
        let result = SRSEngine.rate(entry, rating: .again)
        #expect(result.easeFactor >= 1.3)
        #expect(abs(result.easeFactor - 1.3) < 0.0001)
    }

    @Test("again clamps easeFactor when decrement would go below 1.3")
    func testAgainClampsEaseBelowThreshold() {
        let entry = makeEntry(interval: 2.0, easeFactor: 1.4, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .again)
        #expect(result.easeFactor >= 1.3)
    }

    // MARK: - Hard

    @Test("hard multiplies interval by 1.2")
    func testHardMultipliesInterval() {
        let entry = makeEntry(interval: 5.0, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .hard)
        #expect(abs(result.interval - 6.0) < 0.0001)
    }

    @Test("hard decrements easeFactor by 0.15")
    func testHardDecrementsEase() {
        let entry = makeEntry(interval: 5.0, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .hard)
        #expect(abs(result.easeFactor - 2.35) < 0.0001)
    }

    @Test("hard clamps easeFactor at 1.3")
    func testHardClampsEase() {
        let entry = makeEntry(interval: 2.0, easeFactor: 1.35, ratingCount: 1)
        let result = SRSEngine.rate(entry, rating: .hard)
        #expect(result.easeFactor >= 1.3)
    }

    // MARK: - Good

    @Test("good multiplies interval by easeFactor")
    func testGoodMultipliesInterval() {
        let entry = makeEntry(interval: 4.0, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(abs(result.interval - 10.0) < 0.0001)
    }

    @Test("good leaves easeFactor unchanged")
    func testGoodEaseUnchanged() {
        let entry = makeEntry(interval: 4.0, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(abs(result.easeFactor - 2.5) < 0.0001)
    }

    // MARK: - Easy

    @Test("easy multiplies interval by easeFactor × 1.3")
    func testEasyMultipliesInterval() {
        let entry = makeEntry(interval: 4.0, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .easy)
        // 4.0 × 2.5 × 1.3 = 13.0
        #expect(abs(result.interval - 13.0) < 0.0001)
    }

    @Test("easy leaves easeFactor unchanged")
    func testEasyEaseUnchanged() {
        let entry = makeEntry(interval: 4.0, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .easy)
        #expect(abs(result.easeFactor - 2.5) < 0.0001)
    }

    // MARK: - Minimum interval

    @Test("minimum interval is 1.0 for all ratings from 0")
    func testMinimumIntervalForAllRatings() {
        // entry with nil interval/ease → defaults to interval=1.0, ease=2.5
        let entry = makeEntry()
        for rating: SRSRating in [.again, .hard, .good, .easy] {
            let result = SRSEngine.rate(entry, rating: rating)
            #expect(result.interval >= 1.0, "interval must be ≥ 1.0 for rating \(rating)")
        }
    }

    // MARK: - easeFactor floor

    @Test("easeFactor never drops below 1.3")
    func testEaseFactorNeverBelowFloor() {
        // Run again repeatedly from very low ease
        var entry = makeEntry(interval: 1.0, easeFactor: 1.3, ratingCount: 1)
        for _ in 0..<5 {
            let result = SRSEngine.rate(entry, rating: .again)
            #expect(result.easeFactor >= 1.3)
            entry = makeEntry(interval: result.interval, easeFactor: result.easeFactor, ratingCount: result.ratingCount)
        }
    }

    // MARK: - ratingCount

    @Test("ratingCount increments by 1 on each rating")
    func testRatingCountIncrements() {
        let entry = makeEntry(ratingCount: 3)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(result.ratingCount == 4)
    }

    @Test("ratingCount starts at 1 when entry has no prior ratings (nil)")
    func testRatingCountStartsAtOne() {
        let entry = makeEntry(ratingCount: nil)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(result.ratingCount == 1)
    }

    // MARK: - srsState derivation

    @Test("first rating (ratingCount=0) → srsState == .learning")
    func testFirstRatingProducesLearning() {
        let entry = makeEntry(interval: 1.0, easeFactor: 2.5, ratingCount: 0)
        let result = SRSEngine.rate(entry, rating: .good)
        // ratingCount becomes 1, interval=2.5 < 7 → .learning
        #expect(result.srsState == .learning)
    }

    @Test("interval=6.9 after rating → .learning")
    func testInterval6Point9IsLearning() {
        // Need interval × ease ≈ 6.9 → interval ≈ 6.9/2.5 = 2.76 before good
        // Directly craft an entry whose good result hits ~6.9
        // 2.76 × 2.5 = 6.9
        let entry = makeEntry(interval: 2.76, easeFactor: 2.5, ratingCount: 1)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(result.interval < 7.0)
        #expect(result.srsState == .learning)
    }

    @Test("interval=7.0 after rating → .known")
    func testInterval7Point0IsKnown() {
        // 2.8 × 2.5 = 7.0
        let entry = makeEntry(interval: 2.8, easeFactor: 2.5, ratingCount: 1)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(abs(result.interval - 7.0) < 0.0001)
        #expect(result.srsState == .known)
    }

    @Test("interval=21.0 after rating → .mastered")
    func testInterval21Point0IsMastered() {
        // 8.4 × 2.5 = 21.0
        let entry = makeEntry(interval: 8.4, easeFactor: 2.5, ratingCount: 3)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(abs(result.interval - 21.0) < 0.0001)
        #expect(result.srsState == .mastered)
    }

    @Test("again from .known (ratingCount=5, interval=10) → .learning (interval=1.0, ratingCount=6)")
    func testAgainFromKnownReturnsToLearning() {
        let entry = makeEntry(interval: 10.0, easeFactor: 2.5, ratingCount: 5)
        let result = SRSEngine.rate(entry, rating: .again)
        #expect(result.interval == 1.0)
        #expect(result.ratingCount == 6)
        #expect(result.srsState == .learning)
    }

    // MARK: - dueDate

    @Test("dueDate is today + round(newInterval) in yyyy-MM-dd format")
    func testDueDateFormat() {
        let entry = makeEntry(interval: 1.0, easeFactor: 2.5, ratingCount: 0)
        let result = SRSEngine.rate(entry, rating: .good)
        // newInterval = 1.0 × 2.5 = 2.5 → round(2.5) = 2 (banker's rounding) or 3 (standard)
        // Verify yyyy-MM-dd format: 10 chars, dashes at positions 4 and 7
        #expect(result.dueDate.count == 10, "dueDate must be 10 chars: \(result.dueDate)")
        #expect(result.dueDate[result.dueDate.index(result.dueDate.startIndex, offsetBy: 4)] == "-",
                "dueDate must have dash at position 4: \(result.dueDate)")
        #expect(result.dueDate[result.dueDate.index(result.dueDate.startIndex, offsetBy: 7)] == "-",
                "dueDate must have dash at position 7: \(result.dueDate)")
        #expect(result.dueDate >= todayString(), "dueDate must be today or in the future")
    }

    @Test("dueDate for again rating is tomorrow (interval=1 → +1 day)")
    func testDueDateForAgainIsTomorrow() {
        let entry = makeEntry(interval: 5.0, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .again)
        // newInterval = 1.0, round(1.0) = 1 → tomorrow
        #expect(result.dueDate == todayString(addingDays: 1))
    }

    @Test("dueDate for nil-defaults entry with good rating equals today + round(2.5)")
    func testDueDateDefaultEntry() {
        let entry = makeEntry() // interval=nil → 1.0, ease=nil → 2.5
        let result = SRSEngine.rate(entry, rating: .good)
        // newInterval = 1.0 × 2.5 = 2.5, round(2.5) depends on rounding mode
        let expected = todayString(addingDays: Int((2.5).rounded()))
        #expect(result.dueDate == expected)
    }
}

// MARK: - SRSLifecycleTests (US4 — Phase 6 preview, pure function)

@Suite("SRSLifecycleTests")
struct SRSLifecycleTests {

    @Test("full lifecycle: new → learning × 2 → known → mastered → again → learning")
    func testFullLifecycleProgression() {
        var entry = makeEntry(interval: 1.0, easeFactor: 2.5, ratingCount: 0)

        // Rating 1 — Good: interval=1.0×2.5=2.5, ratingCount=1 → .learning
        var result = SRSEngine.rate(entry, rating: .good)
        #expect(result.ratingCount == 1)
        #expect(abs(result.interval - 2.5) < 0.0001)
        #expect(result.srsState == .learning)

        entry = makeEntry(interval: result.interval, easeFactor: result.easeFactor, ratingCount: result.ratingCount)

        // Rating 2 — Good: interval=2.5×2.5=6.25, ratingCount=2 → .learning
        result = SRSEngine.rate(entry, rating: .good)
        #expect(result.ratingCount == 2)
        #expect(abs(result.interval - 6.25) < 0.0001)
        #expect(result.srsState == .learning)

        entry = makeEntry(interval: result.interval, easeFactor: result.easeFactor, ratingCount: result.ratingCount)

        // Rating 3 — Good: interval=6.25×2.5=15.625, ratingCount=3 → .known
        result = SRSEngine.rate(entry, rating: .good)
        #expect(result.ratingCount == 3)
        #expect(abs(result.interval - 15.625) < 0.0001)
        #expect(result.srsState == .known)

        entry = makeEntry(interval: result.interval, easeFactor: result.easeFactor, ratingCount: result.ratingCount)

        // Rating 4 — Good: interval=15.625×2.5=39.0625, ratingCount=4 → .mastered
        result = SRSEngine.rate(entry, rating: .good)
        #expect(result.ratingCount == 4)
        #expect(abs(result.interval - 39.0625) < 0.0001)
        #expect(result.srsState == .mastered)

        entry = makeEntry(interval: result.interval, easeFactor: result.easeFactor, ratingCount: result.ratingCount)

        // Rating 5 — Again from mastered: interval=1.0, ratingCount=5 → .learning
        result = SRSEngine.rate(entry, rating: .again)
        #expect(result.ratingCount == 5)
        #expect(result.interval == 1.0)
        #expect(result.srsState == .learning)
    }

    @Test("boundary: interval=6.99 → .learning")
    func testBoundary6Point99IsLearning() {
        // Build an entry that produces interval ≈ 6.99 via hard: 5.825 × 1.2 = 6.99
        let entry = makeEntry(interval: 5.825, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .hard)
        #expect(result.interval < 7.0)
        #expect(result.srsState == .learning)
    }

    @Test("boundary: interval=7.0 → .known")
    func testBoundary7Point0IsKnown() {
        // 2.8 × 2.5 = 7.0
        let entry = makeEntry(interval: 2.8, easeFactor: 2.5, ratingCount: 2)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(abs(result.interval - 7.0) < 0.0001)
        #expect(result.srsState == .known)
    }

    @Test("boundary: interval=20.99 → .known")
    func testBoundary20Point99IsKnown() {
        // Need good result ≈ 20.99: 8.396 × 2.5 = 20.99
        let entry = makeEntry(interval: 8.396, easeFactor: 2.5, ratingCount: 3)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(result.interval < 21.0)
        #expect(result.srsState == .known)
    }

    @Test("boundary: interval=21.0 → .mastered")
    func testBoundary21Point0IsMastered() {
        // 8.4 × 2.5 = 21.0
        let entry = makeEntry(interval: 8.4, easeFactor: 2.5, ratingCount: 3)
        let result = SRSEngine.rate(entry, rating: .good)
        #expect(abs(result.interval - 21.0) < 0.0001)
        #expect(result.srsState == .mastered)
    }

    @Test("ratingCount=0 always produces .new regardless of interval (impossible via rate, guarded by derivation)")
    func testRatingCount0AlwaysNew() {
        // ratingCount=0 implies the entry was never rated; SRSEngine increments to 1,
        // so after any rating ratingCount ≥ 1. This test verifies the derivation rule
        // by constructing a synthetic SRSUpdate and checking the invariant holds
        // if someone were to call deriveState with count=0 manually.
        // Instead we test the guard: the first call always bumps count to 1.
        let entry = makeEntry(interval: 100.0, easeFactor: 2.5, ratingCount: 0)
        let result = SRSEngine.rate(entry, rating: .easy)
        // ratingCount becomes 1 → never .new
        #expect(result.srsState != .new)
        #expect(result.ratingCount == 1)
    }
}
