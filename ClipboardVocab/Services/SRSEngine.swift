import Foundation

// MARK: - SRSState

/// The lifecycle state of a vocabulary entry in the spaced-repetition pipeline.
/// Derived after every rating from `ratingCount` and `interval` (see derivation rule below).
///
/// Derivation rule:
/// ```
/// ratingCount == 0         → .new
/// interval < 7             → .learning
/// interval < 21            → .known
/// else                     → .mastered
/// ```
enum SRSState: String, Codable {
    case new      = "new"       // Never rated (ratingCount == 0)
    case learning = "learning"  // Rated ≥ 1 time, interval < 7
    case known    = "known"     // interval ≥ 7
    case mastered = "mastered"  // interval ≥ 21
}

// MARK: - SRSRating

/// The user's recall quality rating for a vocabulary review.
/// Not `Codable` — never persisted directly.
enum SRSRating {
    case again  // Interval resets to 1; easeFactor -= 0.2 (min 1.3)
    case hard   // Interval × 1.2; easeFactor -= 0.15 (min 1.3)
    case good   // Interval × easeFactor; ease unchanged
    case easy   // Interval × easeFactor × 1.3; ease unchanged
}

// MARK: - SRSUpdate

/// Carries the output of `SRSEngine.rate(_:rating:)`.
/// Applied to the DB entry via `VocabularyEntryRepository.applyRating(id:update:)`.
struct SRSUpdate {
    let srsState:    SRSState
    let dueDate:     String   // "YYYY-MM-DD" in local calendar
    let interval:    Double
    let easeFactor:  Double
    let ratingCount: Int
}

// MARK: - SRSEngine

/// Pure SM-2 spaced-repetition scheduling engine.
///
/// All methods are static pure functions: no I/O, no side effects, no stored state.
/// May be called from any thread.
struct SRSEngine {

    // MARK: - SRS

    /// Applies the SM-2 algorithm to `entry` based on the user's recall `rating`.
    ///
    /// Returns an `SRSUpdate` containing all five updated SRS fields.
    /// The caller is responsible for persisting the result via
    /// `VocabularyEntryRepository.applyRating(id:update:)`.
    ///
    /// - Parameters:
    ///   - entry: The vocabulary entry being reviewed. `interval`, `easeFactor`,
    ///     and `ratingCount` default to `1.0`, `2.5`, and `0` when `nil`.
    ///   - rating: The user's recall quality for this review session.
    /// - Returns: A new `SRSUpdate` with recalculated interval, ease, due date,
    ///   rating count, and derived state. Never throws.
    ///
    /// **SM-2 formula per rating:**
    ///
    /// | Rating  | New interval                        | Ease factor change         |
    /// |---------|-------------------------------------|----------------------------|
    /// | `again` | `1.0` (hard reset)                  | `max(1.3, ease − 0.2)`     |
    /// | `hard`  | `max(1.0, interval × 1.2)`          | `max(1.3, ease − 0.15)`    |
    /// | `good`  | `max(1.0, interval × ease)`         | unchanged                  |
    /// | `easy`  | `max(1.0, interval × ease × 1.3)`  | unchanged                  |
    ///
    /// **State derivation rule (applied after every rating using the *new* values):**
    ///
    /// ```
    /// newRatingCount == 0  → .new       (impossible via this method; guard only)
    /// newInterval    < 7   → .learning
    /// newInterval    < 21  → .known
    /// else                 → .mastered
    /// ```
    ///
    /// `dueDate` = today + `round(newInterval)` days, formatted `yyyy-MM-dd` (local calendar).
    static func rate(_ entry: VocabularyEntry, rating: SRSRating) -> SRSUpdate {
        let priorInterval   = entry.interval    ?? 1.0
        let priorEase       = entry.easeFactor  ?? 2.5
        let priorCount      = entry.ratingCount ?? 0

        let newInterval: Double
        let newEase: Double

        switch rating {
        case .again:
            // Complete failure — reset interval to 1 day, penalise ease by 0.2 (floor 1.3)
            newInterval = 1.0
            newEase     = max(1.3, priorEase - 0.2)
        case .hard:
            // Recalled with significant effort — small growth, penalise ease by 0.15 (floor 1.3)
            newInterval = max(1.0, priorInterval * 1.2)
            newEase     = max(1.3, priorEase - 0.15)
        case .good:
            // Recalled correctly — standard SM-2 growth; ease unchanged
            newInterval = max(1.0, priorInterval * priorEase)
            newEase     = priorEase
        case .easy:
            // Recalled with no effort — accelerated growth (×1.3 bonus); ease unchanged
            newInterval = max(1.0, priorInterval * priorEase * 1.3)
            newEase     = priorEase
        }

        let newRatingCount = priorCount + 1
        // Derive state from *new* ratingCount and *new* interval (see derivation table above)
        let newState       = deriveState(ratingCount: newRatingCount, interval: newInterval)
        let newDueDate     = dueDateString(addingDays: Int(newInterval.rounded()))

        return SRSUpdate(
            srsState:    newState,
            dueDate:     newDueDate,
            interval:    newInterval,
            easeFactor:  newEase,
            ratingCount: newRatingCount
        )
    }

    // MARK: - Private helpers

    /// Derives the `SRSState` from the post-rating `ratingCount` and `interval`.
    ///
    /// Thresholds (inclusive lower bound):
    /// - `interval ≥ 21` → `.mastered`
    /// - `interval ≥ 7`  → `.known`
    /// - `ratingCount ≥ 1` → `.learning`
    /// - `ratingCount == 0` → `.new` (entry was never rated)
    private static func deriveState(ratingCount: Int, interval: Double) -> SRSState {
        if ratingCount == 0   { return .new }
        if interval    < 7.0  { return .learning }
        if interval    < 21.0 { return .known }
        return .mastered
    }

    /// Returns today + `days` formatted as `yyyy-MM-dd` in the device's local calendar.
    /// Computed at call time — never cached; safe across midnight.
    private static func dueDateString(addingDays days: Int) -> String {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date())) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar   = cal
        return formatter.string(from: date)
    }
}
