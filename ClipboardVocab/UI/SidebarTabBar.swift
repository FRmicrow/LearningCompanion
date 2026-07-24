import SwiftUI

// MARK: - SidebarTab

/// The four tabs of the vocabulary sidebar.
/// Per `contracts/vocabulary-sidebar.md`.
enum SidebarTab: Hashable, CaseIterable {
    case inbox
    case learn
    case review
    case stats

    var label: String {
        switch self {
        case .inbox:  return L10n.string("tab_inbox_label")
        case .learn:  return L10n.string("tab_learn_label")
        case .review: return L10n.string("tab_review_label")
        case .stats:  return L10n.string("tab_stats_label")
        }
    }

    var symbolName: String {
        switch self {
        case .inbox:  return "tray"
        case .learn:  return "book"
        case .review: return "arrow.clockwise"
        case .stats:  return "chart.bar"
        }
    }
}

// MARK: - SidebarTabBar

/// Bottom tab bar component for the vocabulary sidebar.
///
/// Renders four tab buttons; the active tab is visually highlighted
/// with the accent colour and a filled SF Symbol variant.
struct SidebarTabBar: View {

    let selectedTab: SidebarTab
    let onSelect: (SidebarTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .frame(height: 56)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private func tabButton(for tab: SidebarTab) -> some View {
        let isSelected = tab == selectedTab
        Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? "\(tab.symbolName).fill" : tab.symbolName)
                    .font(.system(size: 18))
                Text(tab.label)
                    .font(.system(size: 10))
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keyEquivalent(for: tab), modifiers: .command)
        .accessibilityLabel(tab.label)
    }

    private func keyEquivalent(for tab: SidebarTab) -> KeyEquivalent {
        switch tab {
        case .inbox:  return "1"
        case .learn:  return "l"
        case .review: return "r"
        case .stats:  return "4"
        }
    }
}
