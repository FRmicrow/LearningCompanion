import SwiftUI
import GRDB

/// The main vocabulary panel hosted inside the `VocabularySidebarView` content area.
///
/// Displays vocabulary entries grouped by capture date (Zone 1),
/// a separate "Old Unretained Words" section for entries older than 7 days (Zone 2),
/// and an empty state placeholder when no entries exist (Zone 3).
///
/// The `List` and empty-state view use `.frame(maxWidth: .infinity)` (no fixed width
/// or height cap) so they fill whatever space `VocabularySidebarView` provides.
/// Per contracts C-24, C-25, C-26 (`specs/011-inbox-layout-fix/contracts/vocabulary-list-layout.md`).
/// Uses GRDB `ValueObservation` for reactive updates.
/// Per `contracts/vocabulary-panel-ui.md`.
struct VocabularyListView: View {

    // MARK: - Dependencies

    let repository: VocabularyEntryRepository
    let translationService: TranslationService

    // MARK: - Bindings (Epic 5 — Add to Learn)

    /// Binding to the active focus session owned by VocabularySidebarView.
    /// When "Add to Learn" constructs a new session it writes here.
    /// Silently overwrites any paused session (C-46).
    @Binding var session: FocusSession?

    /// Called by "Add to Learn" to navigate to the Learn tab.
    var onNavigateToLearn: (() -> Void)?

    // MARK: - State

    @State private var entries: [VocabularyEntry] = []
    @State private var observationTask: Task<Void, Never>? = nil
    /// Controls whether the translation for the focused Inbox item is revealed.
    @State private var isTranslationVisible: Bool = false

    // MARK: - Selection state (Epic 5)

    @State private var isSelecting: Bool = false
    @State private var selectedIDs: Set<Int64> = []

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
            .modifier(InboxKeyboardShortcutsModifier(
                onRevealTranslation: { isTranslationVisible = true },
                onToggleTranslation: { isTranslationVisible.toggle() },
                onMarkKnown: { markKnown() }
            ))
    }

    @ViewBuilder
    private var translationContent: some View {
        VStack(spacing: 0) {
            // MARK: Selection toolbar
            if isSelecting {
                HStack(spacing: 8) {
                    Button(L10n.string("inbox_cancel_button")) {
                        cancelSelection()
                    }
                    .controlSize(.small)

                    Spacer()

                    Button(L10n.string("inbox_delete_selected_button")) {
                        deleteSelected()
                    }
                    .controlSize(.small)
                    .disabled(selectedIDs.isEmpty)

                    Button(L10n.string("inbox_add_to_learn_button")) {
                        addToLearn()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedIDs.isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()
            } else {
                HStack {
                    Spacer()
                    Button(L10n.string("inbox_select_button")) {
                        isSelecting = true
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .background(Color(NSColor.controlBackgroundColor))

                Divider()
            }

            if entries.isEmpty {
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dateGroups, id: \.label) { group in
                        VocabularyDateGroupSection(
                            dateLabel: group.label,
                            entries: group.entries,
                            onRetainToggle: { id, retained in
                                toggleRetained(id: id, retained: retained)
                            },
                            onSave: { entry in
                                save(entry)
                            },
                            onRetryGroup: {
                                try await translationService.retryGroup(entries: group.entries)
                            },
                            onDelete: { entry in
                                delete(entry)
                            },
                            isSelecting: isSelecting,
                            selectedIDs: $selectedIDs
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
                .frame(maxWidth: .infinity)
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func save(_ entry: VocabularyEntry) {
        guard let id = entry.id else { return }
        Task { try? repository.markSaved(id: id) }
    }

    private func toggleRetained(id: Int64, retained: Bool) {
        Task {
            try? repository.markRetained(id: id, retained)
            // ValueObservation will fire and refresh entries automatically
        }
    }

    /// F-104: Mark the first unretained entry as known (retained).
    private func markKnown() {
        guard let entry = entries.first(where: { !$0.isRetained }),
              let id = entry.id else { return }
        toggleRetained(id: id, retained: true)
        isTranslationVisible = false
    }

    private func delete(_ entry: VocabularyEntry) {
        guard let id = entry.id else { return }
        try? repository.delete(id: id)
    }

    // MARK: - Selection actions (Epic 5)

    private func cancelSelection() {
        isSelecting = false
        selectedIDs = []
    }

    private func deleteSelected() {
        let ids = Array(selectedIDs)
        isSelecting = false
        selectedIDs = []
        Task { try? repository.deleteAll(ids: ids) }
    }

    private func addToLearn() {
        let selected = entries.filter { entry in
            guard let id = entry.id else { return false }
            return selectedIDs.contains(id)
        }
        guard !selected.isEmpty else { return }
        session = FocusSession(
            totalCards: selected.count,
            isOnDemand: true,
            cards: selected,
            ratedCount: 0,
            tally: .init(),
            failedCardIDs: []
        )
        isSelecting = false
        selectedIDs = []
        onNavigateToLearn?()
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
                // New entries arriving via observation do NOT receive a pre-selected checkbox (C-42).
                for try await freshEntries in observation.values(in: repository.dbQueue) {
                    entries = freshEntries
                }
            } catch {
                // DB closed or app shutting down — ignore
            }
        }
    }
}

// MARK: - InboxKeyboardShortcutsModifier

/// Handles F-104 keyboard shortcuts for the Inbox tab.
///
/// - Space: reveal translation
/// - ⌘H: toggle translation visibility
/// - Return: mark current item as known
///
/// `.onKeyPress` for Space requires macOS 14+; ⌘H / Return hidden buttons work on macOS 13+.
private struct InboxKeyboardShortcutsModifier: ViewModifier {
    let onRevealTranslation: () -> Void
    let onToggleTranslation: () -> Void
    let onMarkKnown: () -> Void

    func body(content: Content) -> some View {
        content
            // ⌘H and Return via hidden buttons (work on macOS 13+)
            .background {
                Group {
                    Button("") { onToggleTranslation() }
                        .keyboardShortcut("h", modifiers: .command)
                    Button("") { onMarkKnown() }
                        .keyboardShortcut(.return, modifiers: [])
                }
                .hidden()
            }
            // Space via onKeyPress (macOS 14+ only)
            .modifier(SpaceKeyRevealModifier(onReveal: onRevealTranslation))
    }
}

/// Conditionally applies `.onKeyPress(.space)` on macOS 14+.
private struct SpaceKeyRevealModifier: ViewModifier {
    let onReveal: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content
                .onKeyPress(.space) {
                    onReveal()
                    return .handled
                }
        } else {
            content
        }
    }
}
