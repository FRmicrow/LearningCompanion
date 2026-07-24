import SwiftUI

/// Placeholder displayed when the vocabulary list is empty.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(L10n.string("empty_state_message"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("empty_state_message"))
    }
}
