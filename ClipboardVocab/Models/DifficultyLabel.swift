import Foundation

/// User-assigned difficulty annotation for a vocabulary entry.
///
/// Stored in the `difficultyLabel` column of `vocabulary_entries`.
/// Raw string values match the SQL column values exactly.
/// Not used by `SRSEngine` — it is a user annotation only.
enum DifficultyLabel: String, Codable {
    case easy   = "easy"
    case medium = "medium"
    case hard   = "hard"
}
