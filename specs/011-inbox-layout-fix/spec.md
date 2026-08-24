# Feature Specification: Inbox Layout Fix

**Feature Branch**: `011-inbox-layout-fix`

**Created**: 2025-08-24

**Status**: Draft

**Input**: User description: "Dans l'onglet 'boite de réception' Je veux que la liste prenne toute la hauteur de l'écran. Je veux que le bandeau latéral soit bien affiché, aujourd'hui il est tronqué, je ne vois que la moitié du bouton 'statistiques' par exemple"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Full-height Inbox list (Priority: P1)

When the user opens the vocabulary panel and navigates to the Inbox tab, the word list should expand to fill all available vertical space inside the panel. Currently the list is capped at a fixed 500 px height, which leaves an empty grey band below the list on most screens and cuts the list short unnecessarily.

**Why this priority**: This is the primary content area of the app. Wasted vertical space directly reduces the number of words visible without scrolling, degrading the core vocabulary-review experience.

**Independent Test**: Open the panel with at least 10 entries. The word list should fill the full height of the panel content area (between the toolbar above it and the tab bar below it), with no empty gap below.

**Acceptance Scenarios**:

1. **Given** the panel is open and the Inbox tab is selected with multiple entries, **When** the panel height is at its default size, **Then** the word list occupies all vertical space between the selection toolbar and the tab bar, with no visible empty gap below.
2. **Given** the panel is open and the Inbox tab is selected with fewer entries than fit in the view, **When** the panel is displayed, **Then** the list still fills available height (empty space appears as normal list background, not a clipped frame).
3. **Given** the Inbox is empty, **When** the panel is displayed, **Then** the empty-state placeholder is centred in the full available height, not only the top 200 px of the viewport.

---

### User Story 2 - Fully visible sidebar tab bar (Priority: P1)

The bottom tab bar (Inbox, Learn, Review, Statistics) must be fully visible at all times. Currently the "Statistics" button is half-hidden because the panel's vertical size is insufficient or the tab bar is being clipped.

**Why this priority**: A partially visible tab bar makes the app appear broken and prevents reliable navigation to the Statistics tab.

**Independent Test**: Open the panel. All four tab bar buttons (Inbox, Learn, Review, Statistics) must be fully rendered with no clipping or truncation at any edge.

**Acceptance Scenarios**:

1. **Given** the panel is open on any tab, **When** the panel is displayed at its default size, **Then** all four navigation tabs are fully visible and no tab label or icon is clipped.
2. **Given** the panel is open, **When** the user resizes or the popover repositions itself near the bottom of the screen, **Then** the tab bar remains fully visible and the content area shrinks before the tab bar does.
3. **Given** the panel opens for the first time after launch, **When** the user looks at the bottom of the panel, **Then** the Statistics tab button is fully rendered, not partially obscured.

---

### Edge Cases

- What happens when the panel is displayed near the bottom edge of the screen and space is very limited? The tab bar must remain visible; the content area should scroll rather than the tab bar being hidden.
- What happens on a low-resolution display (e.g., 1280×800)? The panel must not exceed the available screen height and the tab bar must remain fully visible.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Inbox word list MUST expand to fill all available vertical space within the panel content area, rather than being constrained to a fixed maximum height.
- **FR-002**: The word list frame MUST use a flexible height that grows with the panel rather than a hard-coded pixel cap (currently `maxHeight: 500`).
- **FR-003**: The sidebar tab bar (containing Inbox, Learn, Review, and Statistics tabs) MUST be fully visible and unclipped at all times.
- **FR-004**: The panel's overall height MUST accommodate the tab bar in full before allocating space to scrollable content.
- **FR-005**: The empty-state placeholder MUST be centred in the full available content area height, not constrained to a fixed 200 px frame.

### Key Entities

- **VocabularyListView**: The SwiftUI view rendering the Inbox tab content, including the word list and the empty-state placeholder.
- **VocabularySidebarView**: The root SwiftUI view hosting the tab bar, the daily progress bar, and the content area for each tab. Currently constrains child content with `.frame(maxWidth: .infinity, maxHeight: .infinity)` but the inner list still caps itself.
- **SidebarTabBar**: The bottom tab bar component that must remain fully visible.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Opening the Inbox tab with 10+ entries shows at least as many rows as the panel height allows, with no empty non-scrollable gap below the last visible row.
- **SC-002**: All four tab bar buttons are fully visible (0 px clipped) at the default panel size on a 1440×900 display.
- **SC-003**: The Statistics tab button is fully visible without the user needing to scroll, resize, or perform any additional interaction after opening the panel.
- **SC-004**: Removing the fixed height cap does not break any existing layout on Learn, Review, or Stats tabs.

## Assumptions

- The panel is an `NSPopover` with a fixed preferred content size set in `AppDelegate` or `VocabularySidebarPanel`; the layout fix must work within that size without changing the popover dimensions.
- The tab bar clipping is caused by the hard-coded `maxHeight: 500` on the `List` frame inside `VocabularyListView`, combined with an overall panel size that is too small; removing the cap and letting SwiftUI layout manage the height should resolve both issues.
- Mobile support is out of scope; this is a macOS-only menu-bar app.
- No new dependencies are required; the fix is purely a SwiftUI layout change.
