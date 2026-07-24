import SwiftUI

/// The "Mots non retenus (>1 semaine)" section rendered at the bottom of the vocabulary panel.
///
/// Displays all vocabulary entries that are older than 7 days and have not been marked as retained.
/// The section hides itself when `entries` is empty.
///
/// Per `contracts/vocabulary-panel-ui.md` — Zone 2.
struct OldUnretainedWordsSection: View {

    // MARK: - Input

    let entries: [VocabularyEntry]
    let onRetainToggle: (Int64, Bool) -> Void
    let onDelete: (VocabularyEntry) -> Void

    // MARK: - Body

    var body: some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries, id: \.id) { entry in
                    if let id = entry.id {
                        VocabularyEntryRow(
                            entry: entry,
                            isRetained: Binding(
                                get: { entry.isRetained },
                                set: { onRetainToggle(id, $0) }
                            ),
                            onDelete: { _ in onDelete(entry) }
                        )
                    }
                }
            } header: {
                Text(L10n.string("old_unretained_section_header"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(L10n.string("old_unretained_section_accessibility_label"))
            }
        }
    }
}
