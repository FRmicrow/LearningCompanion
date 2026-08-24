import SwiftUI

/// Displays a single Learn-mode flashcard.
///
/// The card starts with only the English word visible. Pressing Space (or the
/// Reveal button) uncovers the French translation and reveals four SRS rating
/// buttons. Rating buttons and their keyboard shortcuts are only present in the
/// view hierarchy when `isRevealed == true`, enforcing the gate contract (C-39–C-41).
///
/// Also renders `ReviewMetadataFooter` (F-405) and `DifficultySelector` (F-404)
/// unconditionally — these subviews are implemented in T029 and T032 respectively.
struct LearnCardView: View {

    // MARK: - Dependencies

    let entry: VocabularyEntry
    let repository: VocabularyEntryRepository
    /// Called when the user submits a rating. The card resets `isRevealed` to false.
    var onRate: (SRSRating) -> Void

    // MARK: - State

    @State private var isRevealed: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {

            // Primary word — always visible
            Text(entry.englishText)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            if isRevealed {
                // Translation — visible only after Reveal
                Text(entry.frenchTranslation ?? "")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Rating buttons — only present when revealed (C-39, C-41)
                HStack(spacing: 12) {
                    ratingButton(label: L10n.string("learn_rating_again"), rating: .again, shortcut: "1")
                    ratingButton(label: L10n.string("learn_rating_hard"),  rating: .hard,  shortcut: "2")
                    ratingButton(label: L10n.string("learn_rating_good"),  rating: .good,  shortcut: "3")
                    ratingButton(label: L10n.string("learn_rating_easy"),  rating: .easy,  shortcut: "4")
                }
                .padding(.top, 4)
            } else {
                // Reveal button — active before rating buttons exist
                Button(L10n.string("learn_reveal_button")) {
                    isRevealed = true
                }
                .keyboardShortcut(" ", modifiers: [])
                .buttonStyle(.borderedProminent)
            }

            Spacer(minLength: 8)

            // Metadata footer — always visible (C-53)
            ReviewMetadataFooter(entry: entry)

            // Difficulty selector — always visible (C-49)
            DifficultySelector(entry: entry, repository: repository)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Private helpers

    @ViewBuilder
    private func ratingButton(label: String, rating: SRSRating, shortcut: String) -> some View {
        Button(label) {
            onRate(rating)
            isRevealed = false
        }
        .keyboardShortcut(KeyEquivalent(shortcut.first!), modifiers: [])
        .buttonStyle(.bordered)
    }
}
