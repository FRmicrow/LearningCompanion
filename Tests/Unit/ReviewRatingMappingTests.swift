import Testing
@testable import ClipboardVocab

/// Tests the `ReviewRating.toSRSRating` computed property.
///
/// `ReviewRating` is a pure nested type in `ReviewCardView.swift`.
/// No UI harness or database is required — the mapping is a pure function.
@Suite("ReviewRatingMappingTests")
struct ReviewRatingMappingTests {

    @Test("ReviewRating.medium maps to SRSRating.good (C-57)")
    func testMediumMapsToGood() {
        #expect(ReviewRating.medium.toSRSRating == .good)
    }

    @Test("ReviewRating.easy maps to SRSRating.easy")
    func testEasyMapsToEasy() {
        #expect(ReviewRating.easy.toSRSRating == .easy)
    }

    @Test("ReviewRating.hard maps to SRSRating.hard")
    func testHardMapsToHard() {
        #expect(ReviewRating.hard.toSRSRating == .hard)
    }
}
