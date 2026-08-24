import SwiftUI
import GRDB

/// The SwiftUI root view hosted inside `VocabularySidebarPanel`.
///
/// Owns the tab selection state and the daily progress observation.
/// Per `contracts/vocabulary-sidebar.md` C-08 through C-14.
struct VocabularySidebarView: View {

    // MARK: - Dependencies

    let repository: VocabularyEntryRepository
    let translationService: TranslationService
    /// Called when the user presses Escape inside the panel.
    var onEscape: (() -> Void)?

    // MARK: - State

    @State private var selectedTab: SidebarTab = .inbox
    @State private var dailyProgress: DailyProgress = DailyProgress(count: 0)
    @State private var progressTask: Task<Void, Never>?
    @State private var focusSession: FocusSession?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            DailyProgressBar(progress: dailyProgress)

            contentForTab(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            SidebarTabBar(selectedTab: selectedTab) { tab in
                selectedTab = tab
            }
        }
        .onAppear { startProgressObservation() }
        .onDisappear { progressTask?.cancel() }
        .modifier(EscapeKeyDismissModifier(onEscape: onEscape))
    }

    // MARK: - Tab content

    @ViewBuilder
    private func contentForTab(_ tab: SidebarTab) -> some View {
        switch tab {
        case .inbox:
            VocabularyListView(
                repository: repository,
                translationService: translationService,
                session: $focusSession,
                onNavigateToLearn: { selectedTab = .learn }
            )
        case .learn:
            LearnView(repository: repository, session: $focusSession)
        case .review:
            ReviewView(repository: repository, session: $focusSession)
        case .stats:
            Text(L10n.string("stats_placeholder_label"))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Daily progress observation

    private func startProgressObservation() {
        let observation = ValueObservation.tracking { db in
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.calendar   = Calendar.current
            let todayString = fmt.string(from: Date())
            return try VocabularyEntry
                .filter(Column("triageStatus") == "saved")
                .filter(Column("dueDate") <= todayString)
                .filter(Column("isMastered") == false)
                .fetchCount(db)
        }

        progressTask = Task { @MainActor in
            do {
                for try await count in observation.values(in: repository.dbQueue) {
                    dailyProgress = DailyProgress(count: count)
                }
            } catch {
                // DB closed or app shutting down — ignore
            }
        }
    }
}

// MARK: - EscapeKeyDismissModifier

/// Handles the Escape key to dismiss the sidebar panel.
/// Uses `.onKeyPress` on macOS 14+ and falls back gracefully on macOS 13.
private struct EscapeKeyDismissModifier: ViewModifier {
    let onEscape: (() -> Void)?

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content
                .onKeyPress(.escape) {
                    onEscape?()
                    return .handled
                }
        } else {
            content
        }
    }
}

