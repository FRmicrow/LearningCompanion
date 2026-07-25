import Foundation
import GRDB
import os

/// Manages the GRDB `DatabaseQueue` and handles schema creation / migration.
///
/// Database file: `~/Library/Application Support/ClipboardVocab/vocabulary.sqlite`
/// Schema version tracked via `PRAGMA user_version`.
final class Database {

    // MARK: - Shared instance

    static let shared: Database = {
        do {
            return try Database()
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }()

    // MARK: - Storage

    let dbQueue: DatabaseQueue

    // MARK: - Init

    init(path: String? = nil) throws {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appDir = appSupport.appendingPathComponent("ClipboardVocab", isDirectory: true)
            try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            dbPath = appDir.appendingPathComponent("vocabulary.sqlite").path
        }

        AppLogger.app.info("Ouverture de la base de données : \(dbPath, privacy: .public)")
        dbQueue = try DatabaseQueue(path: dbPath)
        try migrate()
    }

    // MARK: - Migrations

    private func migrate() throws {
        AppLogger.app.debug("Vérification et application des migrations")
        var migrator = DatabaseMigrator()

        // Version 1: initial schema
        migrator.registerMigration("v1") { db in
            try db.create(table: "vocabulary_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("englishText", .text).notNull().unique()
                t.column("frenchTranslation", .text)
                t.column("translationStatus", .text).notNull().defaults(to: "pending")
                t.column("seenCount", .integer).notNull().defaults(to: 1)
                    .check { $0 >= 1 }
                t.column("firstCapturedAt", .datetime).notNull()
                t.column("lastSeenAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_vocabulary_english_text",
                on: "vocabulary_entries",
                columns: ["englishText"]
            )
            try db.create(
                index: "idx_vocabulary_first_captured",
                on: "vocabulary_entries",
                columns: ["firstCapturedAt"]
            )
            try db.create(
                index: "idx_vocabulary_translation_status",
                on: "vocabulary_entries",
                columns: ["translationStatus"]
            )
        }

        // Version 2: add isRetained column (default false = 0)
        migrator.registerMigration("v2") { db in
            try db.alter(table: "vocabulary_entries") { t in
                t.add(column: "isRetained", .boolean).notNull().defaults(to: false)
            }
        }

        // Version 3: add triageStatus column for Inbox capture/triage (Epic 2)
        migrator.registerMigration("v3") { db in
            try db.alter(table: "vocabulary_entries") { t in
                t.add(column: "triageStatus", .text).notNull().defaults(to: "unreviewed")
            }
            try db.create(
                index: "idx_vocabulary_triage_status",
                on: "vocabulary_entries",
                columns: ["triageStatus"]
            )
        }

        // Version 4: add five SRS columns for spaced-repetition engine (Epic 3)
        migrator.registerMigration("v4") { db in
            // SQLite ALTER TABLE only accepts constant defaults — expression defaults
            // (e.g. date('now')) are rejected at runtime even though they work in
            // CREATE TABLE. Each statement is executed separately; dueDate defaults
            // to NULL (all five fields are optional — markSaved sets real values).
            try db.execute(sql: "ALTER TABLE vocabulary_entries ADD COLUMN srsState    TEXT    DEFAULT 'new'")
            try db.execute(sql: "ALTER TABLE vocabulary_entries ADD COLUMN dueDate     TEXT")
            try db.execute(sql: "ALTER TABLE vocabulary_entries ADD COLUMN interval    REAL    DEFAULT 1.0")
            try db.execute(sql: "ALTER TABLE vocabulary_entries ADD COLUMN easeFactor  REAL    DEFAULT 2.5")
            try db.execute(sql: "ALTER TABLE vocabulary_entries ADD COLUMN ratingCount INTEGER DEFAULT 0")
            try db.create(
                index: "idx_vocabulary_due_date",
                on: "vocabulary_entries",
                columns: ["dueDate"]
            )
        }

        try migrator.migrate(dbQueue)
    }
}
