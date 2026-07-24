import Testing
import Foundation
@testable import ClipboardVocab

@Suite("VocabularyPanel Grouping Tests")
struct VocabularyPanelTests {

    // MARK: - Helpers

    private func makeEntry(id: Int64, text: String, daysAgo: Double, retained: Bool = false) -> VocabularyEntry {
        let date = Date(timeIntervalSinceNow: -daysAgo * 24 * 3600)
        return VocabularyEntry(
            id: id,
            englishText: text,
            frenchTranslation: nil,
            translationStatus: .pending,
            seenCount: 1,
            firstCapturedAt: date,
            lastSeenAt: date,
            isRetained: retained
        )
    }

    // MARK: - Date grouping

    @Test("Entries on two different days form two groups")
    func testDateGrouping_groupsByCalendarDay() {
        let today = makeEntry(id: 1, text: "ephemeral", daysAgo: 0)
        let yesterday = makeEntry(id: 2, text: "transient", daysAgo: 1)
        let todayAlso = makeEntry(id: 3, text: "fleeting", daysAgo: 0)

        let entries = [today, yesterday, todayAlso]

        let calendar = Calendar.current
        let grouped = Dictionary(
            grouping: entries,
            by: { calendar.dateComponents([.year, .month, .day], from: $0.firstCapturedAt) }
        )

        #expect(grouped.keys.count == 2, "Expected 2 date groups")

        let todayKey = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let todayGroup = grouped[todayKey] else {
            Issue.record("Expected a group for today")
            return
        }
        #expect(todayGroup.count == 2)

        let texts = Set(todayGroup.map(\.englishText))
        #expect(texts == ["ephemeral", "fleeting"])
    }

    // MARK: - Old unretained filter

    @Test("Old unretained filter excludes retained and recent entries")
    func testOldUnretained_filterLogic() {
        let oldUnretained = makeEntry(id: 1, text: "archaic", daysAgo: 8, retained: false)
        let oldRetained   = makeEntry(id: 2, text: "obsolete", daysAgo: 9, retained: true)
        let recent        = makeEntry(id: 3, text: "modern",   daysAgo: 2, retained: false)

        let cutoff = Date(timeIntervalSinceNow: -7 * 24 * 3600)
        let result = [oldUnretained, oldRetained, recent].filter {
            !$0.isRetained && $0.firstCapturedAt < cutoff
        }

        #expect(result.count == 1)
        #expect(result[0].englishText == "archaic")
    }
}
