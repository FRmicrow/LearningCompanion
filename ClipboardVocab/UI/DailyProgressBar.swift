import SwiftUI

// MARK: - DailyProgress

/// Value type representing today's vocabulary capture progress.
/// Per `contracts/vocabulary-sidebar.md`.
struct DailyProgress {
    let count: Int
    let target: Int

    init(count: Int, target: Int = 20) {
        self.count = count
        self.target = target
    }

    /// Clamped 0.0...1.0 fraction for use with `ProgressView`.
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(Double(count) / Double(target), 1.0)
    }

    /// Human-readable label e.g. "5 / 20 words".
    var label: String {
        "\(count) / \(target) \(L10n.string("words_label"))"
    }
}

// MARK: - DailyProgressBar

/// Progress header component shown at the top of every sidebar tab view.
///
/// Displays today's capture count relative to a daily target using a
/// native `ProgressView`. Per `contracts/vocabulary-sidebar.md` C-12, C-13.
struct DailyProgressBar: View {

    let progress: DailyProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progress.label)
                .font(.caption)
                .foregroundColor(.secondary)
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
