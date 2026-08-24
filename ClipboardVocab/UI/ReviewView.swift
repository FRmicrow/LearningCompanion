import SwiftUI
import GRDB

/// The Review tab content view.
///
/// Mirrors `LearnView` structurally. Shows French translation first; Reveal
/// uncovers English. Uses the same `FocusSession?` binding as `LearnView` —
/// both tabs share a single queue snapshot owned by `VocabularySidebarView`.
///
/// This sharing means switching tabs mid-session does not reset progress (R-3, C-15).
struct ReviewView: View {

    // MARK: - Dependencies

    let repository: VocabularyEntryRepository
    @Binding var session: FocusSession?

    // MARK: - State

    @State private var dueEntries: [VocabularyEntry] = []
    @State private var observationTask: Task<Void, Never>?
    @State private var showCompletion: Bool = false
    @State private var showInlineError: Bool = false

    // MARK: - Body

    var body: some View {
        Group {
            if showCompletion, let s = session {
                SessionCompletionView(
                    ratedCount: s.ratedCount,
                    tally: s.tally
                ) {
                    session = nil
                    showCompletion = false
                }
            } else if let s = session {
                activeSessionView(s)
            } else if dueEntries.isEmpty {
                emptyStateView
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startObservation() }
        .onDisappear { observationTask?.cancel() }
    }

    // MARK: - Sub-views

    private var idleView: some View {
        VStack(spacing: 12) {
            Button(String(format: L10n.string("session_header"), dueEntries.count)) {
                startSession()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyStateView: some View {
        Text(L10n.string("session_empty_state"))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }

    @ViewBuilder
    private func activeSessionView(_ s: FocusSession) -> some View {
        if let card = s.current {
            VStack(spacing: 0) {
                // Session header + progress counter
                HStack {
                    Text(String(format: L10n.string("session_header"), s.totalCards))
                        .font(.headline)
                    Spacer()
                    Text(String(format: L10n.string("session_progress"), s.ratedCount, s.totalCards))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ReviewCardView(entry: card, repository: repository) { rating in
                    submitRating(card: card, rating: rating)
                }
                .overlay(alignment: .top) {
                    if showInlineError {
                        Text(L10n.string("session_write_error"))
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(6)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startSession() {
        guard !dueEntries.isEmpty else { return }
        session = FocusSession(
            totalCards: dueEntries.count,
            isOnDemand: false,
            cards: dueEntries,
            ratedCount: 0,
            tally: .init(),
            failedCardIDs: []
        )
    }

    private func submitRating(card: VocabularyEntry, rating: SRSRating) {
        Task {
            do {
                let update = SRSEngine.rate(card, rating: rating)
                try repository.applyRating(id: card.id!, update: update)
                await MainActor.run {
                    session?.recordRating(rating)
                    session?.advance()
                    if session?.isComplete == true {
                        showCompletion = true
                    }
                }
            } catch {
                // Write failure — re-queue the card once (C-45)
                await MainActor.run {
                    showInlineError = true
                    session?.appendRetry(card)
                    session?.advance()
                }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run { showInlineError = false }
                }
            }
        }
    }

    // MARK: - Observation

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> [VocabularyEntry] in
            let today: String = {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                fmt.calendar = Calendar.current
                return fmt.string(from: Date())
            }()
            return try VocabularyEntry
                .filter(Column("triageStatus") == VocabularyEntry.TriageStatus.saved.rawValue)
                .filter(Column("dueDate") <= today)
                .order(Column("dueDate").asc)
                .fetchAll(db)
        }
        observationTask = Task { @MainActor in
            do {
                for try await entries in observation.values(in: repository.dbQueue) {
                    dueEntries = entries
                }
            } catch {
                // DB closed or app shutting down
            }
        }
    }
}
