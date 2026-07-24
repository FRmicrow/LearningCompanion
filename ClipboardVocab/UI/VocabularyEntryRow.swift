import SwiftUI

/// A single row in the vocabulary list.
///
/// Displays English text, French translation (or pending badge), seen count,
/// an "ok" retained checkbox, and a delete button.
///
/// Per `contracts/vocabulary-panel-ui.md`.
struct VocabularyEntryRow: View {

    // MARK: - Dependencies

    let entry: VocabularyEntry
    @Binding var isRetained: Bool
    let onDelete: (VocabularyEntry) -> Void

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 8) {

            // MARK: Retained checkbox
            Toggle(isOn: $isRetained) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(L10n.string("retained_toggle_accessibility_label", entry.englishText))

            // MARK: Word + translation
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.englishText)
                    .font(.headline)
                    .foregroundColor(isRetained ? .secondary : .primary)
                    .strikethrough(isRetained)

                if entry.translationStatus == .translated,
                   let translation = entry.frenchTranslation {
                    Text("→ \(translation)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(L10n.string("translation_pending_label"))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                        .accessibilityLabel(L10n.string("translation_pending_label"))
                }

                if entry.seenCount > 1 {
                    Text(L10n.string("seen_count_format", entry.seenCount))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Vu \(entry.seenCount) fois")
                }
            }

            Spacer()

            // MARK: Delete button
            Button {
                onDelete(entry)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Supprimer \(entry.englishText)")
        }
        .padding(.vertical, 4)
        .opacity(isRetained ? 0.6 : 1.0)
    }
}
