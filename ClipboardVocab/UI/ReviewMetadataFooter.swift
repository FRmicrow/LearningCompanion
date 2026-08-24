import SwiftUI

/// Displays "Last review" and "Next review" relative date labels below a card.
///
/// Fully implemented in T029 (US4). This stub compiles cleanly and is replaced
/// with the real implementation in Phase 6.
struct ReviewMetadataFooter: View {

    let entry: VocabularyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(L10n.string("card_last_review")): \(lastReviewLabel)")
            Text("\(L10n.string("card_next_review")): \(nextReviewLabel)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Private helpers

    private var todayStr: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = Calendar.current
        return fmt.string(from: Date())
    }

    private var lastReviewLabel: String {
        RelativeDateFormatter.lastReviewedLabel(from: entry.lastReviewedDate, today: todayStr)
    }

    private var nextReviewLabel: String {
        RelativeDateFormatter.nextReviewLabel(from: entry.dueDate, today: todayStr)
    }
}
