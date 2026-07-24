import SwiftUI
import GRDB

/// The main vocabulary panel hosted inside the `NSPopover`.
///
/// Displays vocabulary entries grouped by capture date (Zone 1),
/// a separate "Old Unretained Words" section for entries older than 7 days (Zone 2),
/// and an empty state placeholder when no entries exist (Zone 3).
///
/// Uses GRDB `ValueObservation` for reactive updates.
/// Per `contracts/vocabulary-panel-ui.md`.
struct VocabularyListView: View {

    // MARK: - Dependencies

    let repository: VocabularyEntryRepository
    let translationService: TranslationService

    // MARK: - State

    @State private var entries: [VocabularyEntry] = []
    @State private var observationTask: Task<Void, Never>? = nil

    // MARK: - Derived data

    /// Entries grouped by calendar day, sorted newest-first.
    private var dateGroups: [(label: String, entries: [VocabularyEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(
            grouping: entries,
            by: { calendar.dateComponents([.year, .month, .day], from: $0.firstCapturedAt) }
        )
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        return grouped
            .sorted { lhs, rhs in
                // Compare by year then month then day descending
                let l = lhs.key, r = rhs.key
                if l.year != r.year { return (l.year ?? 0) > (r.year ?? 0) }
                if l.month != r.month { return (l.month ?? 0) > (r.month ?? 0) }
                return (l.day ?? 0) > (r.day ?? 0)
            }
            .map { (components, groupEntries) in
                let date = calendar.date(from: components) ?? Date()
                return (label: formatter.string(from: date), entries: groupEntries)
            }
    }

    /// Entries older than 7 days that have not been marked as retained.
    private var oldUnretained: [VocabularyEntry] {
        let cutoff = Date(timeIntervalSinceNow: -7 * 24 * 3600)
        return entries.filter { !$0.isRetained && $0.firstCapturedAt < cutoff }
    }

    // MARK: - Body

    var body: some View {
        translationContent
            .onAppear { startObservation() }
            .onDisappear { observationTask?.cancel() }
            .retryPendingOnAppear(for: translationService)
    }

    @ViewBuilder
    private var translationContent: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                EmptyStateView()
                    .frame(width: 380, height: 200)
            } else {
                List {
                    ForEach(dateGroups, id: \.label) { group in
                        VocabularyDateGroupSection(
                            dateLabel: group.label,
                            entries: group.entries,
                            onRetainToggle: { id, retained in
                                toggleRetained(id: id, retained: retained)
                            },
                            onRetryGroup: {
                                try await translationService.retryGroup(entries: group.entries)
                            },
                            onDelete: { entry in
                                delete(entry)
                            }
                        )
                    }

                    OldUnretainedWordsSection(
                        entries: oldUnretained,
                        onRetainToggle: { id, retained in
                            toggleRetained(id: id, retained: retained)
                        },
                        onDelete: { entry in
                            delete(entry)
                        }
                    )
                }
                .frame(width: 380)
                .frame(maxHeight: 500)
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func toggleRetained(id: Int64, retained: Bool) {
        Task {
            try? repository.markRetained(id: id, retained)
            // ValueObservation will fire and refresh entries automatically
        }
    }

    private func delete(_ entry: VocabularyEntry) {
        guard let id = entry.id else { return }
        try? repository.delete(id: id)
    }

    // MARK: - Live data via GRDB ValueObservation

    private func startObservation() {
        let observation = ValueObservation.tracking { db in
            try VocabularyEntry
                .order(Column("firstCapturedAt").desc)
                .fetchAll(db)
        }

        observationTask = Task { @MainActor in
            do {
                for try await freshEntries in observation.values(in: repository.dbQueue) {
                    entries = freshEntries
                }
            } catch {
                // DB closed or app shutting down — ignore
            }
        }
    }
}
