import SwiftUI

/// Displays a single Review-mode flashcard.
///
/// Review mode is the mirror of Learn mode: the French translation is shown first;
/// Reveal uncovers the English word and shows three rating buttons
/// (Easy / Medium / Hard). Medium maps to `.good` via `ReviewRating.toSRSRating`
/// (C-57, C-58) — the SRS engine never sees a raw "Medium" value.
///
/// Rating buttons and keyboard shortcuts are only present in the view hierarchy
/// when `isRevealed == true`, enforcing the gate contract (C-39–C-41).
///
/// Also renders `ReviewMetadataFooter` (F-405) and `DifficultySelector` (F-404)
/// unconditionally (C-49, C-53).
struct ReviewCardView: View {

    // MARK: - Dependencies

    let entry: VocabularyEntry
    let repository: VocabularyEntryRepository
    /// Called when the user submits a rating (already mapped to `SRSRating`).
    var onRate: (SRSRating) -> Void

    // MARK: - State

    @State private var isRevealed: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {

            // Primary text — French translation, always visible
            Text(entry.frenchTranslation ?? "")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            if isRevealed {
                // English word — visible only after Reveal
                Text(entry.englishText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Rating buttons — only present when revealed (C-39, C-41)
                HStack(spacing: 12) {
                    ratingButton(label: L10n.string("review_rating_easy"),   review: .easy,   shortcut: "1")
                    ratingButton(label: L10n.string("review_rating_medium"), review: .medium, shortcut: "2")
                    ratingButton(label: L10n.string("review_rating_hard"),   review: .hard,   shortcut: "3")
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
    private func ratingButton(label: String, review: ReviewRating, shortcut: String) -> some View {
        Button(label) {
            onRate(review.toSRSRating)
            isRevealed = false
        }
        .keyboardShortcut(KeyEquivalent(shortcut.first!), modifiers: [])
        .buttonStyle(.bordered)
    }
}

// MARK: - ReviewRating

/// Maps the three Review-mode UI labels to their corresponding `SRSRating` values.
///
/// The SRS engine never sees "Medium" directly — callers always convert via
/// `toSRSRating` before calling `SRSEngine.rate(_:rating:)` or `applyRating`.
/// This makes the mapping unit-testable without a UI harness (T022, C-57, C-58).
enum ReviewRating {
    case easy
    case medium
    case hard

    /// Maps this Review label to the canonical `SRSRating` passed to the SRS engine.
    var toSRSRating: SRSRating {
        switch self {
        case .easy:   return .easy
        case .medium: return .good   // C-57: Medium → .good
        case .hard:   return .hard
        }
    }
}
