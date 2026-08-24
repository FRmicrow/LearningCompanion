import Foundation

/// Pure utility for converting `YYYY-MM-DD` date strings to human-readable
/// relative labels such as "Yesterday", "Today", "In 3 days".
///
/// All methods accept an explicit `todayString` parameter rather than reading
/// `Date()` directly, keeping them deterministic and easily unit-testable.
enum RelativeDateFormatter {

    // MARK: - Last Reviewed Label

    /// Returns a human-readable label for when an entry was last reviewed.
    ///
    /// - Parameters:
    ///   - dateString: The stored `lastReviewedDate` value (`"YYYY-MM-DD"`), or `nil` if never reviewed.
    ///   - todayString: Today's date as `"YYYY-MM-DD"` (pass `todayString()` from callers).
    /// - Returns:
    ///   - `"Never"` when `dateString` is `nil`
    ///   - `"Today"` when `dateString == todayString`
    ///   - `"Yesterday"` when `dateString` is 1 day before today
    ///   - `"N days ago"` for all other past dates
    static func lastReviewedLabel(from dateString: String?, today todayString: String) -> String {
        guard let dateString else { return "Never" }
        let days = dayDifference(from: dateString, to: todayString)
        switch days {
        case 0:  return "Today"
        case 1:  return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    // MARK: - Next Review Label

    /// Returns a human-readable label for when an entry is next due for review.
    ///
    /// - Parameters:
    ///   - dateString: The stored `dueDate` value (`"YYYY-MM-DD"`), or `nil` if not yet scheduled.
    ///   - todayString: Today's date as `"YYYY-MM-DD"`.
    /// - Returns:
    ///   - `"Today"` when `dateString` is `nil`, today, or in the past
    ///   - `"Tomorrow"` when `dateString` is 1 day ahead
    ///   - `"In N days"` for all other future dates
    static func nextReviewLabel(from dateString: String?, today todayString: String) -> String {
        guard let dateString else { return "Today" }
        let days = dayDifference(from: todayString, to: dateString)
        switch days {
        case ...0: return "Today"
        case 1:    return "Tomorrow"
        default:   return "In \(days) days"
        }
    }

    // MARK: - Private helpers

    /// Number of calendar days from `fromString` to `toString` using `Calendar.current`.
    /// Positive means `toString` is after `fromString`.
    private static func dayDifference(from fromString: String, to toString: String) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar   = Calendar.current
        guard
            let fromDate = formatter.date(from: fromString),
            let toDate   = formatter.date(from: toString)
        else { return 0 }
        let cal = Calendar.current
        let components = cal.dateComponents([.day], from: fromDate, to: toDate)
        return components.day ?? 0
    }
}
