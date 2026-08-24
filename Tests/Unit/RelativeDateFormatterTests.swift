import Testing
import Foundation
@testable import ClipboardVocab

/// Unit tests for `RelativeDateFormatter`.
///
/// All tests pass fixed `dateString` and `todayString` literals — never `Date()` —
/// so results are fully deterministic regardless of when the test suite runs.
@Suite("RelativeDateFormatterTests")
struct RelativeDateFormatterTests {

    // MARK: - lastReviewedLabel

    @Test("lastReviewedLabel returns Never for nil input")
    func testLastReviewedNil() {
        let result = RelativeDateFormatter.lastReviewedLabel(from: nil, today: "2025-07-23")
        #expect(result == "Never")
    }

    @Test("lastReviewedLabel returns Today for same-day input")
    func testLastReviewedSameDay() {
        let result = RelativeDateFormatter.lastReviewedLabel(from: "2025-07-23", today: "2025-07-23")
        #expect(result == "Today")
    }

    @Test("lastReviewedLabel returns Yesterday for 1 day ago")
    func testLastReviewedYesterday() {
        let result = RelativeDateFormatter.lastReviewedLabel(from: "2025-07-22", today: "2025-07-23")
        #expect(result == "Yesterday")
    }

    @Test("lastReviewedLabel returns N days ago for multiple days")
    func testLastReviewedNDaysAgo() {
        let result = RelativeDateFormatter.lastReviewedLabel(from: "2025-07-20", today: "2025-07-23")
        #expect(result == "3 days ago")
    }

    // MARK: - nextReviewLabel

    @Test("nextReviewLabel returns Today for nil input")
    func testNextReviewNil() {
        let result = RelativeDateFormatter.nextReviewLabel(from: nil, today: "2025-07-23")
        #expect(result == "Today")
    }

    @Test("nextReviewLabel returns Today for same-day input")
    func testNextReviewSameDay() {
        let result = RelativeDateFormatter.nextReviewLabel(from: "2025-07-23", today: "2025-07-23")
        #expect(result == "Today")
    }

    @Test("nextReviewLabel returns Tomorrow for 1 day ahead")
    func testNextReviewTomorrow() {
        let result = RelativeDateFormatter.nextReviewLabel(from: "2025-07-24", today: "2025-07-23")
        #expect(result == "Tomorrow")
    }

    @Test("nextReviewLabel returns In N days for multiple days ahead")
    func testNextReviewNDaysAhead() {
        let result = RelativeDateFormatter.nextReviewLabel(from: "2025-07-30", today: "2025-07-23")
        #expect(result == "In 7 days")
    }

    @Test("nextReviewLabel returns Today for overdue date (past date)")
    func testNextReviewOverdue() {
        let result = RelativeDateFormatter.nextReviewLabel(from: "2025-07-20", today: "2025-07-23")
        #expect(result == "Today", "Overdue dates should display as Today (due now)")
    }
}
