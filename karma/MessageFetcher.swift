import Foundation
import SQLite3

// MARK: - Errors

enum MessageFetcherError: Error, LocalizedError {
    case permissionDenied
    case databaseOpenFailed
    case schemaVersionError(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Full Disk Access required"
        case .databaseOpenFailed:
            return "Could not open Messages database"
        case .schemaVersionError(let msg):
            return "iMessage schema changed — app may need update: \(msg)"
        case .queryFailed(let msg):
            return "Database query failed: \(msg)"
        }
    }
}

// MARK: - MessageFetcher

class MessageFetcher: MessageFetcherProtocol {
    private let dbPath: String

    init(dbPath: String = NSHomeDirectory() + "/Library/Messages/chat.db") {
        self.dbPath = dbPath
    }

    func fetch(since unixTimestamp: Double) async throws -> [MessageItem] {
        guard PermissionManager.checkFullDiskAccess() else {
            throw MessageFetcherError.permissionDenied
        }

        // Run SQLite work off the main thread
        var results = try await Task.detached(priority: .userInitiated) {
            try self.executeQuery(since: unixTimestamp)
        }.value

        // WAL retry: 0 rows may be a timing artefact — retry once after 500ms
        if results.isEmpty {
            try await Task.sleep(nanoseconds: 500_000_000)
            results = try await Task.detached(priority: .userInitiated) {
                try self.executeQuery(since: unixTimestamp)
            }.value
        }

        return results
    }

    // MARK: - SQLite (synchronous, called from detached task)

    private func executeQuery(since unixTimestamp: Double) throws -> [MessageItem] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK, let db else {
            throw MessageFetcherError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA query_only=ON;", nil, nil, nil)

        try verifySchema(db)

        // Mac Absolute Time epoch is Jan 1, 2001 = unix 978307200
        // chat.db stores dates in nanoseconds since that epoch
        let macNanos = Int64((unixTimestamp - 978_307_200) * 1_000_000_000)

        let sql = """
            SELECT m.text, h.id, m.date
            FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            JOIN handle h ON m.handle_id = h.ROWID
            WHERE m.date > ? AND m.is_from_me = 0 AND m.text IS NOT NULL
            ORDER BY m.date DESC
            LIMIT 5
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MessageFetcherError.queryFailed("prepare failed")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, macNanos)
        return collectRows(stmt)
    }

    private func collectRows(_ stmt: OpaquePointer) -> [MessageItem] {
        var items: [MessageItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let textPtr = sqlite3_column_text(stmt, 0),
                  let senderPtr = sqlite3_column_text(stmt, 1) else { continue }
            let text = String(cString: textPtr)
            let sender = String(cString: senderPtr)
            let macNanos = sqlite3_column_int64(stmt, 2)
            let unixSecs = Double(macNanos) / 1_000_000_000 + 978_307_200
            items.append(MessageItem(
                sender: sender,
                text: text,
                date: Date(timeIntervalSince1970: unixSecs)
            ))
        }
        return items
    }

    // MARK: Schema probe (guards against Apple silently renaming columns)

    private func verifySchema(_ db: OpaquePointer) throws {
        let required: [String: [String]] = [
            "message": ["text", "date", "is_from_me", "handle_id"],
            "handle": ["id"],
            "chat_message_join": ["message_id"]
        ]
        for (table, cols) in required {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                throw MessageFetcherError.schemaVersionError("cannot query \(table)")
            }
            defer { sqlite3_finalize(stmt) }

            var found = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 1) { found.insert(String(cString: ptr)) }
            }
            for col in cols where !found.contains(col) {
                throw MessageFetcherError.schemaVersionError("\(table).\(col) missing")
            }
        }
    }

    // MARK: - Exposed for unit testing

    /// Pure function: convert a Unix timestamp to Mac Absolute Time nanoseconds.
    static func macAbsoluteNanos(from unixTimestamp: Double) -> Int64 {
        Int64((unixTimestamp - 978_307_200) * 1_000_000_000)
    }
}
