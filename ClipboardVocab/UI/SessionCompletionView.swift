import SwiftUI

/// Shown when a Focus Session queue is fully drained.
struct SessionCompletionView: View {

    let ratedCount: Int
    let tally: FocusSession.RatingTally
    var onDismiss: () -> Void
    /// Called when the user taps "Restart Session" (C-51). Builds a new session from the learn pool.
    var onRestart: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(String(format: L10n.string("session_completion_total"), ratedCount))
                .font(.title2.bold())

            Text("Again: \(tally.again)  Hard: \(tally.hard)  Good: \(tally.good)  Easy: \(tally.easy)")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Done") { onDismiss() }
                    .buttonStyle(.bordered)

                if let onRestart {
                    Button(L10n.string("session_restart_button")) { onRestart() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
