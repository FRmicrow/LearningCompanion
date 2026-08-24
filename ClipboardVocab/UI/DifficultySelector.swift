import SwiftUI

/// Easy / Medium / Hard radio selector shown on every card.
///
/// Fully implemented in T032 (US5). This stub compiles cleanly and is replaced
/// with the real implementation in Phase 7.
struct DifficultySelector: View {

    let entry: VocabularyEntry
    let repository: VocabularyEntryRepository

    @State private var selected: DifficultyLabel?

    init(entry: VocabularyEntry, repository: VocabularyEntryRepository) {
        self.entry = entry
        self.repository = repository
        self._selected = State(initialValue: entry.difficultyLabel)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach([DifficultyLabel.easy, .medium, .hard], id: \.self) { label in
                Button(labelString(for: label)) {
                    selected = label
                    Task { try? repository.setDifficultyLabel(id: entry.id!, label: label) }
                }
                .buttonStyle(.bordered)
                .tint(selected == label ? .accentColor : .secondary)
            }
        }
    }

    private func labelString(for label: DifficultyLabel) -> String {
        switch label {
        case .easy:   return L10n.string("difficulty_easy")
        case .medium: return L10n.string("difficulty_medium")
        case .hard:   return L10n.string("difficulty_hard")
        }
    }
}
