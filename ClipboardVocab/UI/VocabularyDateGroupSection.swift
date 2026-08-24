import SwiftUI

/// A single date-group section in the vocabulary panel.
///
/// Renders a section header with the capture date and a "Réessayer la traduction" button,
/// followed by a row for each `VocabularyEntry` in the group.
///
/// Per `contracts/vocabulary-panel-ui.md` — Zone 1.
struct VocabularyDateGroupSection: View {

    // MARK: - Input

    let dateLabel: String
    let entries: [VocabularyEntry]
    let onRetainToggle: (Int64, Bool) -> Void
    let onSave: (VocabularyEntry) -> Void
    /// Called when the retry button is tapped. Returns the number of successful translations.
    /// Throws if the service is wholly unavailable.
    let onRetryGroup: () async throws -> Int
    let onDelete: (VocabularyEntry) -> Void

    // MARK: - Selection state (Epic 5)

    var isSelecting: Bool = false
    @Binding var selectedIDs: Set<Int64>

    // MARK: - State

    @State private var isRetrying = false
    @State private var retryError: String? = nil
    @State private var currentRetryTask: Task<Void, Never>? = nil

    // MARK: - Body

    /// True when at least one entry in this group still needs a translation.
    private var hasPendingEntries: Bool {
        entries.contains { $0.translationStatus == .pending }
    }

    var body: some View {
        Section {
            ForEach(entries, id: \.id) { entry in
                if let id = entry.id {
                    if isSelecting {
                        // Selection mode: show toggle checkbox overlay; tap toggles ID in selectedIDs
                        HStack {
                            Toggle(isOn: Binding(
                                get: { selectedIDs.contains(id) },
                                set: { checked in
                                    if checked { selectedIDs.insert(id) }
                                    else { selectedIDs.remove(id) }
                                }
                            )) {
                                EmptyView()
                            }
                            .toggleStyle(.checkbox)
                            .labelsHidden()

                            VocabularyEntryRow(
                                entry: entry,
                                isRetained: Binding(
                                    get: { entry.isRetained },
                                    set: { onRetainToggle(id, $0) }
                                ),
                                onSave: nil,
                                onDelete: { _ in onDelete(entry) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIDs.contains(id) {
                                    selectedIDs.remove(id)
                                } else {
                                    selectedIDs.insert(id)
                                }
                            }
                        }
                    } else {
                        VocabularyEntryRow(
                            entry: entry,
                            isRetained: Binding(
                                get: { entry.isRetained },
                                set: { onRetainToggle(id, $0) }
                            ),
                            onSave: { onSave($0) },
                            onDelete: { _ in onDelete(entry) }
                        )
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dateLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("\(dateLabel), section")

                    Spacer()

                    if hasPendingEntries {
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.7)
                                .padding(.trailing, 4)
                        } else {
                            Button(L10n.string("retry_group_label")) {
                                    guard !isRetrying else { return }
                                    isRetrying = true
                                    retryError = nil
                                    currentRetryTask?.cancel()
                                    currentRetryTask = Task {
                                        do {
                                            _ = try await onRetryGroup()
                                        } catch {
                                            await MainActor.run { retryError = L10n.string("retry_service_error") }
                                        }
                                        await MainActor.run { isRetrying = false }
                                    }
                                }
                            .buttonStyle(.link)
                            .font(.caption)
                            .accessibilityLabel(L10n.string("retry_group_accessibility_label", dateLabel))
                        }
                    }
                }

                if let error = retryError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
