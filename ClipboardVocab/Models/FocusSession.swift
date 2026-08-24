import Foundation

// MARK: - FocusSession

/// In-memory value type managing the state of an active Learn or Review session.
///
/// Holds the ordered queue of remaining cards, tracks rating progress, and enforces
/// the single-retry rule for write failures. Not persisted to disk — lives in
/// `@State` on the sidebar tab container for the duration of the app session.
///
/// **Single-retry invariant**: `failedCardIDs` records IDs of cards whose write
/// already failed once. `appendRetry` silently no-ops for IDs already in the set,
/// ensuring each card is re-queued at most once per session.
///
/// **`totalCards` is immutable**: set once at session init from the queue snapshot
/// count; never changes even when retry cards are appended. The session header
/// always shows the original snapshot count.
struct FocusSession {

    // MARK: - Immutable session context

    /// Original queue snapshot count. Shown in "Today's Review — N cards" header.
    /// Never mutated, even when retry cards are appended.
    let totalCards: Int

    /// `true` when this session was constructed from an Inbox promotion ("Add to Learn").
    /// `false` for SRS daily-queue sessions and Restart sessions.
    /// Set once at initialisation; never mutated.
    let isOnDemand: Bool

    // MARK: - Mutable session progress

    /// Ordered remaining cards. The first element is always the current card.
    var cards: [VocabularyEntry]

    /// Count of cards successfully rated (write succeeded). Does NOT increment on failure.
    var ratedCount: Int

    /// Per-rating breakdown accumulated during this session.
    var tally: RatingTally

    /// IDs of cards that have already been re-queued once via `appendRetry`.
    /// A card whose ID is in this set will not be re-queued a second time.
    var failedCardIDs: Set<Int64>

    // MARK: - Computed

    /// `true` when the queue is fully drained (including any retried cards).
    var isComplete: Bool { cards.isEmpty }

    /// The card currently being shown, or `nil` when the session is complete.
    var current: VocabularyEntry? { cards.first }

    // MARK: - Mutations

    /// Removes the front card from the queue, advancing to the next one.
    /// Does NOT modify `ratedCount` or `tally`.
    mutating func advance() {
        guard !cards.isEmpty else { return }
        cards.removeFirst()
    }

    /// Appends `entry` to the end of `cards` for a second attempt, **only if**
    /// its ID has not already been added to `failedCardIDs` (single-retry rule).
    ///
    /// After a successful append, inserts `entry.id` into `failedCardIDs`.
    /// If `entry.id` is already in `failedCardIDs`, this is a no-op.
    mutating func appendRetry(_ entry: VocabularyEntry) {
        guard let id = entry.id, !failedCardIDs.contains(id) else { return }
        cards.append(entry)
        failedCardIDs.insert(id)
    }

    /// Increments `ratedCount` by 1 and the corresponding `tally` field.
    /// Call this only after a **successful** `applyRating` write.
    mutating func recordRating(_ rating: SRSRating) {
        ratedCount += 1
        switch rating {
        case .again: tally.again += 1
        case .hard:  tally.hard  += 1
        case .good:  tally.good  += 1
        case .easy:  tally.easy  += 1
        }
    }

    // MARK: - Nested tally

    /// Per-rating accumulator for the session completion screen.
    struct RatingTally {
        var again: Int = 0
        var hard:  Int = 0
        var good:  Int = 0
        var easy:  Int = 0
    }
}
